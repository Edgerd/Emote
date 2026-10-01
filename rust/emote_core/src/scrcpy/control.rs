//! `scrcpy::control` —— 控制消息发送（第 3.1 段）。
//!
//! 复用 `scrcpy-protocol` 的 [`ControlSender`]（把触摸/按键/文本/滚动等 scrcpy 控制消息
//! 序列化到控制通道的 `std::net::TcpStream`，克隆共享同一 socket）。
//!
//! 约定：坐标为**屏幕像素**（scrcpy 协议要求，非归一化）。Emote 侧在 Win/Lin 控制
//! Android 方向调用；本段不涉及视频渲染，也不做输入注入到桌面端（那是第 3.5 段）。

pub use scrcpy_protocol::protocol::control::{ControlMessage, ControlMessageType, Position};
pub use scrcpy_protocol::ControlSender;

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Read;
    use std::net::TcpListener;

    /// 建立一对 loopback `TcpStream`：返回 (服务端写入端, 客户端读取端)。
    fn loopback_pair() -> (std::net::TcpStream, std::net::TcpStream) {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind 失败");
        let addr = listener.local_addr().unwrap();
        let client = std::net::TcpStream::connect(addr).expect("connect 失败");
        let (server, _) = listener.accept().expect("accept 失败");
        (server, client)
    }

    #[test]
    fn touch_down_serializes_to_scrcpy_layout() {
        let (server, mut client) = loopback_pair();
        let sender = ControlSender::new(server, 1080, 1920);
        sender.send_touch_down(10, 20).expect("发送 touch_down 失败");

        // InjectTouchEvent 布局：1B type + 1B action + 8B pointer_id + (4B x,4B y,2B w,2B h)
        //                      + 2B pressure + 4B action_button + 4B buttons = 32 字节
        let mut buf = [0u8; 32];
        client.read_exact(&mut buf).expect("读取控制字节失败");
        assert_eq!(buf[0], ControlMessageType::InjectTouchEvent as u8); // =2
        assert_eq!(buf[1], 0); // action Down
        assert_eq!(&buf[2..10], &u64::MAX.to_be_bytes()); // POINTER_ID_MOUSE
        assert_eq!(&buf[10..14], &10u32.to_be_bytes()); // x
        assert_eq!(&buf[14..18], &20u32.to_be_bytes()); // y
        assert_eq!(&buf[18..20], &1080u16.to_be_bytes()); // screen_width
        assert_eq!(&buf[20..22], &1920u16.to_be_bytes()); // screen_height
    }

    #[test]
    fn text_serializes_with_length_prefix() {
        let (server, mut client) = loopback_pair();
        let sender = ControlSender::new(server, 100, 100);
        sender.send_text("hi").expect("发送 text 失败");

        // InjectText 布局：1B type + 4B 长度 + 文本字节
        let mut buf = [0u8; 7];
        client.read_exact(&mut buf).expect("读取 text 字节失败");
        assert_eq!(buf[0], ControlMessageType::InjectText as u8); // =1
        assert_eq!(&buf[1..5], &2u32.to_be_bytes());
        assert_eq!(&buf[5..7], b"hi");
    }

    #[test]
    fn key_press_sends_down_then_up() {
        let (server, mut client) = loopback_pair();
        let sender = ControlSender::new(server, 50, 50);
        // KEYCODE_A = 29，metastate = 0
        sender.send_key_press(29, 0).expect("发送 key 失败");

        // InjectKeycode 布局：1B type + 1B action + 4B keycode + 4B repeat + 4B metastate = 14 字节
        // key_press = down + up 共 28 字节
        let mut buf = [0u8; 28];
        client.read_exact(&mut buf).expect("读取 key 字节失败");
        assert_eq!(buf[0], ControlMessageType::InjectKeycode as u8); // =0
        assert_eq!(buf[1], 0); // Down
        assert_eq!(&buf[2..6], &29u32.to_be_bytes()); // keycode
        assert_eq!(buf[14], ControlMessageType::InjectKeycode as u8);
        assert_eq!(buf[15], 1); // Up
        assert_eq!(&buf[16..20], &29u32.to_be_bytes());
    }
}
