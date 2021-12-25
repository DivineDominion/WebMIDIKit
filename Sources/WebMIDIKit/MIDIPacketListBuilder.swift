import CoreMIDI
///
/// heavily based on MIDIPacketList.Builder
/// at most, we should be processing `128 * 3` bytes so i guess 512 should be enough
/// this is similar to MIDIPacketList.Builder but it uses pointer for append instead of [UInt8]
/// and also it doesn't allocate in append
///
public final class MIDIPacketListBuilder {
    //
    var list: UnsafeMutablePointer<MIDIPacketList>

    // used for iterating
    var first: UnsafeMutablePointer<MIDIPacket>

    // used for appending
    var tail: UnsafeMutablePointer<MIDIPacket>

    let byteSize: Int
    var occupied: Int

    let totalByteSize: Int

    public init(byteSize: Int) {
        //
        // the 14 (0xe) is taken from MIDI::LegacyPacketList::create although i'm not sure why it's 14
        //

        let totalByteSize = byteSize + 0xe
        let list = malloc(totalByteSize).assumingMemoryBound(to: MIDIPacketList.self)
        let first = MIDIPacketListInit(list)

        self.totalByteSize = totalByteSize
        self.byteSize = byteSize
        self.list = list
        self.first = first
        self.tail = first
        self.occupied = 0
    }

//    var byteSize1: Int {
//        MIDIPacketList.sizeInBytes(pktList: list)
//    }

    var numPackets: Int {
        Int(self.list.pointee.numPackets)
    }

    public var remaining: Int {
        byteSize - occupied
    }

    public func append(timestamp: MIDITimeStamp, data: UnsafeRawBufferPointer) {
        let ptr = data.bindMemory(to: UInt8.self)
        self.append(timestamp: timestamp, data: ptr)
    }

    public func append(timestamp: MIDITimeStamp, data: [UInt8]) {
        data.withUnsafeBufferPointer {
            self.append(timestamp: timestamp, data: $0)
        }
    }

    ///
    /// according to core-midi (the rust binding), the tail is not adjusted if the timestamp is the same as the previous one
    /// and if there is enough space left in the current packet
    /// if the new data is at a different timestamp than the old data
    ///
    public func append(timestamp: MIDITimeStamp, data: UnsafeBufferPointer<UInt8>) {
//        print("append length before \(self.tail.pointee.length)")
        assert(data.count <= self.remaining)

        let newTail = MIDIPacketListAdd(
            self.list,
            self.totalByteSize,
            self.tail,
            timestamp,
            data.count,
            data.baseAddress!
        )

//        assert(newTail != .null)

        //
        // if the timestamp is different from the last timestamp
        // MIDIPacketListAdd will prepend the timestamp before the
        // data which will increase the consumed size by 12 bytes
        //
        let consumed: Int
        if newTail != self.tail {
            consumed = self.tail.byteDistance(to: newTail)
        } else {
            consumed = data.count
        }

        self.occupied += consumed
        self.tail = newTail
    }

    public var isEmpty: Bool {
        self.occupied == 0
    }

    public func clear() {
        self.first = MIDIPacketListInit(self.list)
        self.tail = self.first
        self.occupied = 0
    }

//    public func resize(size: Int) {
//        guard size > self.byteSize else { return }
//        let totalByteSize = size + 0xe
//        self.list = realloc(self.list, totalByteSize).assumingMemoryBound(to: MIDIPacketList.self)
//        self.totalByteSize = totalByteSize
//    }

    deinit {
        free(self.list)
    }

    @inline(__always)
    public func withUnsafePointer<Result>(_ body: (UnsafePointer<MIDIPacketList>) -> Result) -> Result {
        body(self.list)
    }

    @inline(__always)
    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) -> R) -> R {
        return withUnsafePointer {
            body(UnsafeRawBufferPointer(start: $0, count: self.occupied))
        }
    }
}

extension UnsafeMutablePointer {
//    static var null: Self? {
//        Self(nil)
//    }

    func byteDistance(to other: Self) -> Int {
        self.withMemoryRebound(to: UInt8.self, capacity: 1) { old in
            other.withMemoryRebound(to: UInt8.self, capacity: 1) { new in
                old.distance(to: new)
            }
        }
    }
}

extension MIDIPacketListBuilder: Sequence {
    public typealias Element = UnsafePointer<MIDIPacket>

    public func makeIterator() -> AnyIterator<Element> {
        self.list.makeIterator()
    }
}

extension UnsafePointer where Pointee == MIDIPacket {
//    public var startIndex: Int {
//        fatalError()
//    }
//
//    public var endIndex: Int {
//        fatalError()
//    }

    @inline(__always)
    public var count: Int {
        Int(self.pointee.length)
    }

//    @inline(__always)
//    public func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) -> R) -> R {
//        body(withUnsafePointer(to: pointee.data) {
//            UnsafeRawBufferPointer(start: $0, count: count)
//        })
//    }

        @inline(__always)
        public func withUnsafeBytes<R>(_ body: (UnsafePointer<UInt8>) -> R) -> R {
            body(withUnsafePointer(to: pointee.data) {
                $0.withMemoryRebound(to: UInt8.self, capacity: self.count) {
                    $0
                }
            })
        }

//    @inline(__always)
//    public subscript(index: Int) -> UInt8 {
//        assert(index < count)
//        return withUnsafeBytes { $0[index] }
//    }
}



extension UnsafeMutablePointer: Sequence where Pointee == MIDIPacketList {
    public typealias Element = UnsafePointer<MIDIPacket>

    public func makeIterator() -> AnyIterator<Element> {
        var idx = 0
        let count = self.pointee.numPackets

        return withUnsafeMutablePointer(to: &pointee.packet) { ptr in
            var p = ptr
            return AnyIterator {
                guard idx < count else { return nil }
                defer {
                    p = MIDIPacketNext(p)
                    idx += 1
                }
                return UnsafePointer(p)
//                return p
            }
        }
    }
}

extension UnsafeRawBufferPointer : Equatable {
    @inline(__always)
    public static func ==(lhs: Self, rhs: Self) -> Bool {
        guard lhs.count == rhs.count else { return false }
        return memcmp(lhs.baseAddress, rhs.baseAddress, lhs.count) == 0
    }
}

extension MIDIPacketListBuilder : Equatable {
    public static func ==(lhs: MIDIPacketListBuilder, rhs: MIDIPacketListBuilder) -> Bool {
        guard lhs.occupied == rhs.occupied else { return false }
        return lhs.withUnsafeBytes { fst in
            rhs.withUnsafeBytes { snd in
                fst == snd
            }
        }
    }
}
import AVFoundation

public typealias AUMIDIPacketBlock = (AUEventSampleTime, UInt8, UnsafePointer<MIDIPacket>) -> Void
public typealias AUMIDIPacketListBuilderBlock = (AUEventSampleTime, UInt8, MIDIPacketListBuilder) -> Void

extension AUAudioUnit {
    public var scheduleMIDIPacketBlock: AUMIDIPacketBlock? {
        guard let block = self.scheduleMIDIEventBlock else { return nil }
        return {(ts, channel, ptr) in
            ptr.withUnsafeBytes {
                block(ts, channel, ptr.count, $0)
            }
        }
    }

    public var scheduleMIDIPacketListBuilderBlock: AUMIDIPacketListBuilderBlock? {
        guard let block = self.scheduleMIDIPacketBlock else { return nil }
        return {(ts, channel, list) in
            for e in list {
                block(ts, channel, e)
            }
        }

    }
}
