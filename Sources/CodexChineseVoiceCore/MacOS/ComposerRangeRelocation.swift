import Foundation

extension CodexComposerEditor {
    func relocatedRange(
        _ range: NSRange,
        from previous: String,
        to current: String
    ) -> NSRange? {
        let oldUnits = Array(previous.utf16)
        let newUnits = Array(current.utf16)
        guard range.location >= 0, range.length >= 0,
              range.location <= oldUnits.count,
              range.length <= oldUnits.count - range.location else {
            return nil
        }
        guard oldUnits != newUnits else { return range }

        var prefixLength = 0
        while prefixLength < min(oldUnits.count, newUnits.count),
              oldUnits[prefixLength] == newUnits[prefixLength] {
            prefixLength += 1
        }
        var suffixLength = 0
        while suffixLength < oldUnits.count - prefixLength,
              suffixLength < newUnits.count - prefixLength,
              oldUnits[oldUnits.count - suffixLength - 1]
                == newUnits[newUnits.count - suffixLength - 1] {
            suffixLength += 1
        }

        let oldChangeEnd = oldUnits.count - suffixLength
        if oldChangeEnd <= range.location {
            let location = range.location + newUnits.count - oldUnits.count
            return location >= 0 ? NSRange(location: location, length: range.length) : nil
        }
        if prefixLength >= NSMaxRange(range) { return range }
        return nil
    }
}
