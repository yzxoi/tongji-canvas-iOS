import Testing
import Foundation
@testable import TongJiCanvas

// Each test uses its own unique key so tests are fully concurrent-safe.
// No global deleteAll() needed — keys are cleaned up with defer.
struct KeychainHelperTests {

    @Test func saveAndRead() {
        let key = "kh_saveAndRead_\(UUID().uuidString)"
        defer { KeychainHelper.delete(key: key) }
        KeychainHelper.save(key: key, value: "test_value")
        #expect(KeychainHelper.read(key: key) == "test_value")
    }

    @Test func readMissingKeyReturnsNil() {
        #expect(KeychainHelper.read(key: "kh_definitely_not_stored_\(UUID().uuidString)") == nil)
    }

    @Test func deleteRemovesKey() {
        let key = "kh_deleteRemoves_\(UUID().uuidString)"
        KeychainHelper.save(key: key, value: "test_value")
        KeychainHelper.delete(key: key)
        #expect(KeychainHelper.read(key: key) == nil)
    }

    @Test func overwriteExistingKey() {
        let key = "kh_overwrite_\(UUID().uuidString)"
        defer { KeychainHelper.delete(key: key) }
        KeychainHelper.save(key: key, value: "old_value")
        KeychainHelper.save(key: key, value: "new_value")
        #expect(KeychainHelper.read(key: key) == "new_value")
    }

    @Test func handlesEmptyString() {
        let key = "kh_empty_\(UUID().uuidString)"
        defer { KeychainHelper.delete(key: key) }
        KeychainHelper.save(key: key, value: "")
        #expect(KeychainHelper.read(key: key) == "")
    }

    @Test func handlesSpecialCharacters() {
        let key = "kh_special_\(UUID().uuidString)"
        defer { KeychainHelper.delete(key: key) }
        let special = "_canvas_middle_session=abc123; token=xyz/+/==; domain=.tongji.edu.cn"
        KeychainHelper.save(key: key, value: special)
        #expect(KeychainHelper.read(key: key) == special)
    }

    @Test func deleteAllClearsItems() {
        let key1 = "kh_all1_\(UUID().uuidString)"
        let key2 = "kh_all2_\(UUID().uuidString)"
        KeychainHelper.save(key: key1, value: "v1")
        KeychainHelper.save(key: key2, value: "v2")
        KeychainHelper.deleteAll()
        #expect(KeychainHelper.read(key: key1) == nil)
        #expect(KeychainHelper.read(key: key2) == nil)
    }
}
