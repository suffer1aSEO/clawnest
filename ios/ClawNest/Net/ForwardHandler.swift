import NIOCore

/// Pipes bytes from its own channel straight to a peer channel, and vice-versa when paired.
/// Two of these glue the local loopback socket (that URLSession connects to) to the SSH
/// direct-tcpip channel, reproducing JSch's `setPortForwardingL` from the Android client.
///
/// autoRead is disabled on both channels; each handler pulls the next chunk in
/// channelReadComplete so nothing is read before the peer is wired up (no lost handshake bytes).
/// `Channel.writeAndFlush` is thread-safe across event loops, so the two paired handlers may
/// live on different loops (the SSH loop vs. the local server loop).
final class ForwardHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer

    private let peer: Channel
    init(peer: Channel) { self.peer = peer }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        peer.writeAndFlush(unwrapInboundIn(data), promise: nil)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        context.read()
    }

    func channelInactive(context: ChannelHandlerContext) {
        peer.close(mode: .all, promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
        peer.close(mode: .all, promise: nil)
    }
}
