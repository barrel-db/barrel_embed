"""Tests for uvloop integration and async server functionality."""

import asyncio
import sys
import pytest


class TestUvloopDetection:
    """Test uvloop detection and setup."""

    def test_uvloop_detection_flag(self):
        """Test _USING_UVLOOP flag is set correctly."""
        from barrel_embed.server import _USING_UVLOOP
        assert isinstance(_USING_UVLOOP, bool)
        # If uvloop is importable, flag should be True
        try:
            import uvloop
            assert _USING_UVLOOP is True
        except ImportError:
            assert _USING_UVLOOP is False

    def test_event_loop_policy_set(self):
        """Test event loop uses uvloop policy when available."""
        try:
            import uvloop
            policy = asyncio.get_event_loop_policy()
            assert isinstance(policy, uvloop.EventLoopPolicy), \
                f"Expected uvloop.EventLoopPolicy, got {type(policy)}"
        except ImportError:
            pytest.skip("uvloop not installed")


class TestAsyncServer:
    """Test async server functionality with uvloop."""

    @pytest.mark.asyncio
    async def test_async_operation_runs(self):
        """Test basic async operations work with uvloop."""
        await asyncio.sleep(0.01)
        loop = asyncio.get_event_loop()
        assert loop is not None

    @pytest.mark.asyncio
    async def test_concurrent_tasks(self):
        """Test concurrent task execution with uvloop."""
        results = []

        async def task(n):
            await asyncio.sleep(0.01)
            results.append(n)

        await asyncio.gather(task(1), task(2), task(3))
        assert sorted(results) == [1, 2, 3]

    @pytest.mark.asyncio
    async def test_asyncio_primitives(self):
        """Test asyncio primitives work correctly with uvloop."""
        lock = asyncio.Lock()
        async with lock:
            assert lock.locked()
        assert not lock.locked()

        event = asyncio.Event()
        assert not event.is_set()
        event.set()
        assert event.is_set()


class TestAsyncEmbedServer:
    """Test AsyncEmbedServer base class."""

    def test_server_import(self):
        """Test server module can be imported."""
        from barrel_embed.server import AsyncEmbedServer
        assert AsyncEmbedServer is not None

    def test_server_is_abstract(self):
        """Test AsyncEmbedServer is abstract and cannot be instantiated directly."""
        from barrel_embed.server import AsyncEmbedServer
        with pytest.raises(TypeError):
            AsyncEmbedServer()

    @pytest.mark.asyncio
    async def test_concrete_server_creation(self):
        """Test a concrete implementation can be created."""
        from barrel_embed.server import AsyncEmbedServer

        class TestServer(AsyncEmbedServer):
            def load_model(self):
                return True

            def handle_info(self):
                return {"ok": True, "model": "test"}

            def embed_sync(self, texts):
                return {"ok": True, "embeddings": [[0.1, 0.2] for _ in texts]}

        server = TestServer()
        assert server is not None
        assert server.load_model() is True

    @pytest.mark.asyncio
    async def test_dispatch_info(self):
        """Test dispatch handles info action."""
        from barrel_embed.server import AsyncEmbedServer

        class TestServer(AsyncEmbedServer):
            def load_model(self):
                return True

            def handle_info(self):
                return {"ok": True, "model": "test", "dim": 128}

            def embed_sync(self, texts):
                return {"ok": True, "embeddings": [[0.1] * 128 for _ in texts]}

        server = TestServer()
        result = await server.dispatch({"action": "info"})
        assert result["ok"] is True
        assert result["model"] == "test"
        assert result["dim"] == 128

    @pytest.mark.asyncio
    async def test_dispatch_embed(self):
        """Test dispatch handles embed action."""
        from barrel_embed.server import AsyncEmbedServer

        class TestServer(AsyncEmbedServer):
            def load_model(self):
                return True

            def handle_info(self):
                return {"ok": True}

            def embed_sync(self, texts):
                return {"ok": True, "embeddings": [[0.1, 0.2, 0.3] for _ in texts]}

        server = TestServer()
        result = await server.dispatch({"action": "embed", "texts": ["hello", "world"]})
        assert result["ok"] is True
        assert len(result["embeddings"]) == 2
        assert result["embeddings"][0] == [0.1, 0.2, 0.3]

    @pytest.mark.asyncio
    async def test_dispatch_unknown_action(self):
        """Test dispatch handles unknown action."""
        from barrel_embed.server import AsyncEmbedServer

        class TestServer(AsyncEmbedServer):
            def load_model(self):
                return True

            def handle_info(self):
                return {"ok": True}

            def embed_sync(self, texts):
                return {"ok": True, "embeddings": []}

        server = TestServer()
        result = await server.dispatch({"action": "unknown"})
        assert result["ok"] is False
        assert "unknown" in result["error"].lower()

    @pytest.mark.asyncio
    async def test_handle_embed_empty_list(self):
        """Test handle_embed with empty list."""
        from barrel_embed.server import AsyncEmbedServer

        class TestServer(AsyncEmbedServer):
            def load_model(self):
                return True

            def handle_info(self):
                return {"ok": True}

            def embed_sync(self, texts):
                return {"ok": True, "embeddings": [[0.1] for _ in texts]}

        server = TestServer()
        result = await server.handle_embed([])
        assert result["ok"] is True
        assert result["embeddings"] == []

    @pytest.mark.asyncio
    async def test_handle_embed_invalid_input(self):
        """Test handle_embed with invalid input types."""
        from barrel_embed.server import AsyncEmbedServer

        class TestServer(AsyncEmbedServer):
            def load_model(self):
                return True

            def handle_info(self):
                return {"ok": True}

            def embed_sync(self, texts):
                return {"ok": True, "embeddings": []}

        server = TestServer()

        # Not a list
        result = await server.handle_embed("not a list")
        assert result["ok"] is False

        # List with non-string
        result = await server.handle_embed(["valid", 123])
        assert result["ok"] is False
        assert "texts[1]" in result["error"]
