import Testing
@testable import QRBotCore

@Test func extractsExampleStartParameter() throws {
    let start = try BotStart(qr: "https://t.me/somebot?start=7-1793284285-FxxN8uYXaVmu", expectedBot: "somebot")
    #expect(start.parameter == "7-1793284285-FxxN8uYXaVmu")
    #expect(start.message == "/start 7-1793284285-FxxN8uYXaVmu")
}

@Test func acceptsOfficialTGLinkAndUsernameCase() throws {
    let start = try BotStart(qr: "tg://resolve?start=abc_123-XYZ&domain=SomeBot", expectedBot: "somebot")
    #expect(start.username == "somebot")
    #expect(start.parameter == "abc_123-XYZ")
}

@Test(arguments: [
    "https://t.me/otherbot?start=abc",
    "https://t.me.evil.example/somebot?start=abc",
    "https://evil.example/somebot?start=abc",
    "https://t.me@evil.example/somebot?start=abc",
    "https://evil.example@t.me/somebot?start=abc",
    "http://t.me/somebot?start=abc",
    "https://t.me:443/somebot?start=abc",
    "https://t.me/somebot/extra?start=abc",
    "https://t.me/somebot?start=abc#fragment",
    "https://t.me/somebot?start=abc&start=def",
    "https://t.me/somebot?start=abc&url=https://evil.example",
    "https://t.me/somebot?startgroup=abc",
    "tg://resolve?domain=somebot&domain=otherbot&start=abc",
    "tg://resolve?domain=otherbot&start=abc",
    "tg://resolve/path?domain=somebot&start=abc",
    "tg://login?token=abc",
    "https://t.me/%73omebot?start=abc"
]) func rejectsDestinationSubstitutionAndAmbiguity(_ qr: String) {
    #expect(throws: BotLinkError.self) { try BotStart(qr: qr, expectedBot: "somebot") }
}

@Test(arguments: ["", "abc+def", "abc%20def", "%0Ahello", "%00abc", "hello/world", "abc%", "abc%GG", "😀", String(repeating: "a", count: 65)])
func rejectsInvalidStartValues(_ value: String) {
    #expect(throws: BotLinkError.self) { try BotStart(qr: "https://t.me/somebot?start=\(value)", expectedBot: "somebot") }
}

@Test func validatesBoundaryAndPercentDecoding() throws {
    #expect(try BotStart(qr: "https://t.me/somebot?start=\(String(repeating: "a", count: 64))", expectedBot: "somebot").parameter.count == 64)
    #expect(try BotStart(qr: "https://t.me/somebot?start=%61bc", expectedBot: "somebot").parameter == "abc")
    #expect(throws: BotLinkError.self) { try BotStart(qr: "https://t.me/somebot?start=x", expectedBot: "@somebot") }
}
