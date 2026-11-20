// SPDX-License-Identifier: GPL-3.0-only

// Compiled into the pinned ZIPFoundation module for the standalone probe.
extension Archive {
    public var probeEntryCount: UInt64 { totalNumberOfEntriesInCentralDirectory }
}
