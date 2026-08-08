"""The connection decisions inside `make_engine` — SSL for remote hosts, transaction-pooler handling,
idle-connection recycling. Pure and connection-free where possible, so the security-relevant SSL
choice is asserted without a live remote database (which the test box does not have).
"""

import logging
import ssl

from sqlalchemy import make_url
from sqlalchemy.pool import NullPool

from agent_server.db.session import _connect_args, _is_local_host, make_engine


def _args(url: str) -> tuple[dict[str, object], bool]:
    return _connect_args(make_url(url))


def test_local_hosts_stay_plaintext() -> None:
    # Loopback, private/LAN IPs, and short compose/service names — NOT just "db" (the old allowlist
    # forced TLS onto any local service not named db and crashed it).
    for host in (
        "db", "localhost", "127.0.0.1", "[::1]",  # IPv6 loopback is bracketed in a URL
        "postgres", "database", "local-db",
        "192.168.1.5", "10.0.0.3", "172.16.0.9",
    ):
        args, txn = _args(f"postgresql+asyncpg://u:p@{host}:5432/x")
        assert "ssl" not in args, host
        assert txn is False


def test_is_local_host_edges() -> None:
    assert _is_local_host("") is True                 # hostless URL
    assert _is_local_host("LOCALHOST") is True         # case-insensitive
    assert _is_local_host("host.docker.internal") is False  # dotted -> remote
    assert _is_local_host("aws-0-eu-west-1.pooler.supabase.com") is False


def test_remote_host_gets_verifying_tls() -> None:
    args, txn = _args("postgresql+asyncpg://u:p@aws-0-eu-west-1.pooler.supabase.com:5432/postgres")
    ctx = args["ssl"]
    assert isinstance(ctx, ssl.SSLContext)
    # A context that does not verify is not a TLS check — assert the default hardening held.
    assert ctx.verify_mode == ssl.CERT_REQUIRED
    assert ctx.check_hostname is True
    assert txn is False  # session pooler: prepared statements work, no special handling


def test_explicit_verifying_ssl_in_url_is_left_alone() -> None:
    args, _ = _args("postgresql+asyncpg://u:p@db.ref.supabase.co:5432/postgres?ssl=verify-full")
    assert "ssl" not in args  # defer to the URL, do not double-configure


def test_insecure_ssl_on_remote_is_honoured_but_warns(caplog) -> None:
    with caplog.at_level(logging.WARNING, logger="agent_server.db"):
        args, _ = _args("postgresql+asyncpg://u:p@db.ref.supabase.co:5432/postgres?ssl=require")
    assert "ssl" not in args  # honoured (not overridden with a context)
    assert "NOT enforced" in caplog.text  # but never silent


def test_transaction_pooler_disables_prepared_statements() -> None:
    # Port 6543 = Supavisor transaction mode: BOTH caches off + unique statement names, or a name
    # collides across clients sharing one pooled backend.
    args, txn = _args("postgresql+asyncpg://u:p@aws-0-eu-west-1.pooler.supabase.com:6543/postgres")
    assert txn is True
    assert args["statement_cache_size"] == 0
    assert args["prepared_statement_cache_size"] == 0
    name_func = args["prepared_statement_name_func"]
    assert callable(name_func)
    n1, n2 = name_func(), name_func()
    assert n1 != n2 and n1.startswith("__asyncpg_")  # unique per call
    assert isinstance(args["ssl"], ssl.SSLContext)  # still verified TLS on the pooler


async def test_make_engine_keeps_recycling_queue_pool_even_on_transaction_pooler() -> None:
    # NullPool would force a TCP+TLS handshake per request; the pooler is built for clients to hold
    # connections. pool_recycle guards against the pooler silently reaping idle ones.
    engine = make_engine("postgresql+asyncpg://u:p@aws-0-eu-west-1.pooler.supabase.com:6543/postgres")
    try:
        assert not isinstance(engine.pool, NullPool)
        assert engine.pool._recycle == 1800
    finally:
        await engine.dispose()
