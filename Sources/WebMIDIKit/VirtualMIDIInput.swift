public final class VirtualMIDIInput: MIDIInput {
    override init(client: MIDIClient, endpoint: MIDIEndpoint) {
        super.init(client: client, endpoint: endpoint)
        self.endpoint.assignUniqueID()
    }

//    deinit {
//        self.endpoint.dispose()
//    }
}
