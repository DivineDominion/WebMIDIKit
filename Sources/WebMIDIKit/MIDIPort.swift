import CoreMIDI

/// This interface represents a MIDI input or output port.
/// See [spec](https://www.w3.org/TR/webmidi/#midiport-interface)
public class MIDIPort : Identifiable, Codable {

    internal private(set) final var ref: MIDIPortRef

    internal private(set) final weak var client: MIDIClient!
    internal final let endpoint: MIDIEndpoint

    internal init(client: MIDIClient, endpoint: MIDIEndpoint) {
        self.client = client
        self.endpoint = endpoint
        self.ref = 0

        if endpoint.isVirtual {
            endpoint.assignUniqueID()
        }
    }

    public required init(from decoder: Decoder) throws {
        fatalError()
    }

    public func encode(to encoder: Encoder) throws {
        fatalError()
    }

    
    ///
    /// A unique ID of the port. This can be used by developers to remember ports
    /// the user has chosen for their application. This is maintained across
    /// instances of the application - e.g., when the system is rebooted - and a
    /// device is removed from the system. Applications may want to cache these
    /// ids locally to re-create a MIDI setup. Applications may use the comparison
    /// of id of MIDIPorts to test for equality.
    ///
    public final var id: Int {
        return endpoint.id
    }

    ///
    /// The manufacturer of the port.
    ///
    public final var manufacturer: String? {
        return endpoint.manufacturer
    }

    ///
    /// The system name of the port.
    ///
    public final var name: String? {
        return endpoint.name
    }

    ///
    /// The full name of the port.
    ///
    public final var displayName: String? {
        return endpoint.displayName
    }

    ///
    /// A descriptor property to distinguish whether the port is an input or an
    /// output port. For MIDIOutput, this must be "output". For MIDIInput, this
    /// must be "input".
    ///
    public final var type: MIDIPortType {
        return endpoint.type
    }

    ///
    /// The version of the port.
    ///
    public final var version: Int {
        return endpoint.version
    }

    ///
    /// The state of the connection to the device.
    ///
    public final var connection: MIDIPortConnectionState {
        return ref == 0 ? .closed : .open
    }

    public final var state: MIDIPortDeviceState {
        return endpoint.state
    }

    ///
    /// nonstandard
    ///
    public final var isVirtual: Bool {
        self.endpoint.isVirtual
    }

    ///
    /// gets called when the port state changes (open/closed are called,
    /// or the device endpoint gets disconnected.
    ///
    public final var onStateChange: ((MIDIPort) -> ())? = nil

    ///
    /// establishes a connection
    ///
    public final func open() {
        guard connection != .open else { return }

        switch type {
        case .input:
            let `self` = self as! MIDIInput
            ref = MIDIInputPortCreate(ref: client.ref) {
                `self`.onMIDIMessage?($0)
            }

            OSAssert(MIDIPortConnectSource(ref, endpoint.ref, nil))

        case .output:
            ref = MIDIOutputPortCreate(ref: client.ref)
        }

        onStateChange?(self)
    }

    // it's about onmidimessage2
    //    public final func open2() {
    //        guard connection != .open else { return }
    //
    //        switch type {
    //        case .input:
    //            let `self` = self as! MIDIInput
    //            ref = MIDIInputPortCreate(ref: client.ref) {
    //                `self`.onMIDIMessage2?($0)
    //            }
    //
    //            OSAssert(MIDIPortConnectSource(ref, endpoint.ref, nil))
    //
    //        case .output:
    //            ref = MIDIOutputPortCreate(ref: client.ref)
    //        }
    //
    //        onStateChange?(self)
    //    }

    ///
    /// Closes the port.
    ///
    public final func close() {
        guard connection != .closed else { return }

        switch type {
        case .input:
            OSAssert(MIDIPortDisconnectSource(ref, endpoint.ref))
        case .output:
            endpoint.flush()
        }

        ref = 0
        onStateChange?(self)
        onStateChange = nil
    }

    ///
    /// according to the docs, virtual endpoints need to be disposed
    ///
    deinit {
        if self.isVirtual {
            self.endpoint.dispose()
        }
    }
}

extension MIDIPort : CustomStringConvertible {
    public final var description: String {
        let type: String

        switch (self.type, self.isVirtual) {
        case (.input, true):
            type = "VirtualMIDIInput"
        case (.input, false):
            type = "MIDIInput"
        case (.output, true):
            type = "VirtualMIDIOutput"
        case (.output, false):
            type = "MIDIOutput"
        }
        return "\(type) \(name) by \(manufacturer), connection: \(connection) (id: \(id))"
    }
}

extension MIDIPort : Equatable {
    public static func ==(lhs: MIDIPort, rhs: MIDIPort) -> Bool {
        return lhs.endpoint == rhs.endpoint
    }
}

extension MIDIPort : Comparable {
    public static func <(lhs: MIDIPort, rhs: MIDIPort) -> Bool {
        return lhs.endpoint < rhs.endpoint
    }
}

extension MIDIPort : Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(endpoint.hashValue)
    }
}

//func sequence(first: UnsafePointer<MIDIPacketList>) -> AnyIterator<MIDIEvent> {
//    var ptr = first
//    let count = Int(first.pointee.numPackets)
//
//    return AnyIterator {
//        nil
//    }
//    fatalError()
////    return sequence(first: first) { _ in
//////        UnsafePointer($0)
////        fatalError()
////    }.prefix(count)
//}
////
////@inline(__always) fileprivate
////func MIDIInputPortCreate(ref: MIDIClientRef, readmidi: @escaping (MIDIEvent) -> ()) -> MIDIPortRef {
////    var port = MIDIPortRef()
////    OSAssert(MIDIInputPortCreateWithBlock(ref, "MIDI input" as CFString, &port) {
////        lst, srcconref in
////        sequence(first: lst).forEach(readmidi)
////    })
////    return port
////}



@inline(__always) fileprivate
func MIDIInputPortCreate(
    ref: MIDIClientRef,
    readmidi: @escaping (UnsafePointer<MIDIPacketList>) -> Void
) -> MIDIPortRef {
    var port = MIDIPortRef()
    OSAssert(MIDIInputPortCreateWithBlock(ref, "MIDI input" as CFString, &port) {
        list, _ in
        readmidi(list)
//        lst.pointee.forEach(readmidi)

    })
    return port
}

//@inline(__always) fileprivate
//func MIDIInputPortCreate2(ref: MIDIClientRef, readmidi: @escaping (MIDIEvent2) -> ()) -> MIDIPortRef {
//    var port = MIDIPortRef()
//    OSAssert(MIDIInputPortCreateWithBlock(ref, "MIDI input" as CFString, &port) {
//        lst, srcconref in
//        //        lst.pointee.forEach(readmidi)
//    })
//    return port
//}


@inline(__always) fileprivate
func MIDIOutputPortCreate(ref: MIDIClientRef) -> MIDIPortRef {
    var port = MIDIPortRef()
    OSAssert(MIDIOutputPortCreate(ref, "MIDI output" as CFString, &port))
    return port
}
