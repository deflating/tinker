#!/usr/bin/env python3
"""
Familiar Mini server — serves static files AND proxies WebSocket
connections to the Familiar server, all on one port.
This avoids iOS Safari blocking cross-port ws:// connections.

Usage: python3 serve.py [--port 8090] [--ws-target localhost:8385]
"""

import asyncio
import argparse
import mimetypes
from pathlib import Path
from http import HTTPStatus

import websockets
from websockets.asyncio.server import serve as ws_serve
from websockets.http11 import Response

STATIC_DIR = Path(__file__).parent


async def process_request(connection, request):
    """Handle HTTP requests for static files. Return None for WebSocket upgrades."""
    # If this is a WebSocket upgrade, let it through
    if request.headers.get("Upgrade", "").lower() == "websocket":
        return None

    # Serve static files
    req_path = request.path.split('?')[0]
    if req_path == '/':
        req_path = '/index.html'

    file_path = (STATIC_DIR / req_path.lstrip('/')).resolve()

    # Security check
    if not str(file_path).startswith(str(STATIC_DIR.resolve())):
        return Response(HTTPStatus.FORBIDDEN, "Forbidden\n", websockets.Headers())

    if file_path.is_file():
        content_type = mimetypes.guess_type(str(file_path))[0] or 'application/octet-stream'
        body = file_path.read_bytes()
        headers = websockets.Headers({
            "Content-Type": content_type,
            "Content-Length": str(len(body)),
            "Cache-Control": "no-cache",
        })
        return Response(HTTPStatus.OK, "", headers, body)

    return Response(HTTPStatus.NOT_FOUND, "Not Found\n", websockets.Headers())


async def proxy_handler(websocket, ws_target):
    """Proxy WebSocket messages between client and Familiar server."""
    uri = f"ws://{ws_target}"
    try:
        async with websockets.connect(uri) as upstream:
            async def client_to_server():
                try:
                    async for msg in websocket:
                        await upstream.send(msg)
                except websockets.exceptions.ConnectionClosed:
                    pass

            async def server_to_client():
                try:
                    async for msg in upstream:
                        await websocket.send(msg)
                except websockets.exceptions.ConnectionClosed:
                    pass

            done, pending = await asyncio.wait(
                [asyncio.create_task(client_to_server()),
                 asyncio.create_task(server_to_client())],
                return_when=asyncio.FIRST_COMPLETED,
            )
            for task in pending:
                task.cancel()
    except Exception as e:
        print(f"Proxy error: {e}")


async def run_server(port, ws_target):
    async def handler(websocket):
        await proxy_handler(websocket, ws_target)

    async with ws_serve(
        handler,
        "0.0.0.0",
        port,
        process_request=process_request,
    ) as server:
        print(f"Familiar Mini serving on http://0.0.0.0:{port}")
        print(f"WebSocket proxy → ws://{ws_target}")
        await asyncio.Future()  # run forever


def main():
    parser = argparse.ArgumentParser(description='Familiar Mini server')
    parser.add_argument('--port', type=int, default=8090, help='Port to serve on')
    parser.add_argument('--ws-target', default='localhost:8385', help='Familiar WebSocket server')
    args = parser.parse_args()
    asyncio.run(run_server(args.port, args.ws_target))


if __name__ == '__main__':
    main()
