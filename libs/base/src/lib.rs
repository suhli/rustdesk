pub mod config;
pub mod fs;
pub mod keyboard;
pub mod platform;
pub mod protos;

pub use protos::message as message_proto;

#[cfg(test)]
mod tests {
    use super::message_proto::{
        native_touch_contact::Phase, NativeTouchContact, PointerDeviceEvent,
    };
    use hbb_common::protobuf::Message;

    #[test]
    fn native_touch_preserves_contact_ids_and_signed_desktop_coordinates() {
        for phase in [
            Phase::Down,
            Phase::Move,
            Phase::Up,
            Phase::Cancel,
            Phase::CancelAll,
        ] {
            let mut event = PointerDeviceEvent::new();
            event.set_native_touch(NativeTouchContact {
                phase: phase.into(),
                id: 9,
                x: -1440,
                y: -100,
                ..Default::default()
            });
            let bytes = event.write_to_bytes().unwrap();
            let read = PointerDeviceEvent::parse_from_bytes(&bytes).unwrap();
            let contact = read.native_touch();
            assert_eq!(
                (
                    contact.phase.enum_value().unwrap(),
                    contact.id,
                    contact.x,
                    contact.y
                ),
                (phase, 9, -1440, -100)
            );
        }
    }
}
