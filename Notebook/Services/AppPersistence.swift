import CryptoKit
import Foundation
import Security

struct PersistedNotebookState: Codable {
    var user: NotebookUser
    var notebooks: [SubjectNotebook]
    var authSession: AuthSession?
    var hasCompletedOnboarding: Bool
    var setupStep: SetupStep
    var appTheme: AppTheme
    var selectedStudyMode: MemorizationMode
    var voiceProfile: VoiceProfile
    var onboardingSubjects: [String]
    var comfortSettings: ComfortSettings?
}

struct AppPersistence {
    private let defaults = UserDefaults.standard
    private let key = "notebook.persisted.state.v1"

    func load() -> PersistedNotebookState? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PersistedNotebookState.self, from: data)
    }

    func save(_ state: PersistedNotebookState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

enum CredentialVault {
    private static let service = "com.biswajitacharya.notebook.credentials"

    static func save(email: String, password: String, username: String, faceIDLinked: Bool) throws {
        let account = email.lowercased()
        let record = CredentialRecord(username: username.lowercased(), passwordHash: hash(password), faceIDLinked: faceIDLinked)
        let data = try JSONEncoder().encode(record)
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        item[kSecAttrSynchronizable as String] = kCFBooleanTrue
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw AuthError.secureStorageFailed }
    }

    static func verify(email: String, password: String) throws -> String {
        let account = email.lowercased()
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { throw AuthError.accountNotFound }
        let record = try JSONDecoder().decode(CredentialRecord.self, from: data)
        guard record.passwordHash == hash(password) else { throw AuthError.invalidPassword }
        return record.username
    }

    static func requiresFaceID(email: String) throws -> Bool {
        let record = try record(email: email)
        return record.faceIDLinked
    }

    static func accountExists(email: String) -> Bool {
        (try? record(email: email)) != nil
    }

    private static func record(email: String) throws -> CredentialRecord {
        var query = baseQuery(account: email.lowercased())
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { throw AuthError.accountNotFound }
        return try JSONDecoder().decode(CredentialRecord.self, from: data)
    }

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny
        ]
    }

    private static func hash(_ password: String) -> String {
        let digest = SHA256.hash(data: Data(("notebook.v1." + password).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private struct CredentialRecord: Codable {
        var username: String
        var passwordHash: String
        var faceIDLinked: Bool
    }
}
