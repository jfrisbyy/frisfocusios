//
//  SocialSafetyTests.swift
//  FrisFocusTests
//
//  Pure-function cases for two rules that were wrong against the real
//  backend and are easy to get wrong again:
//
//   • What a Storage upload failure MEANS. Storage answers some
//     failures with HTTP 400 and the real code in the JSON body, and
//     every caller branches on the status (409 "already uploaded",
//     413 "too large"). Reading only the HTTP status turned a harmless
//     retry of a half-finished post into a permanent failure.
//
//   • What an invite says without its link. The landing page may not
//     render, so the shared words have to carry the @username.
//
//  Nothing here touches the network, the Keychain, or a Store.
//

import Foundation
import Testing
@testable import FrisFocus

@Suite("Storage upload status")
struct StorageUploadStatusTests {

    private func body(_ json: String) -> Data { Data(json.utf8) }

    @Test("A duplicate reported as HTTP 400 reads as 409")
    func duplicateInsideBadRequest() {
        let status = StorageUploadClient.effectiveStatus(
            httpStatus: 400,
            body: body(#"{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}"#)
        )
        #expect(status == 409)
    }

    @Test("A duplicate reported as HTTP 409 stays 409")
    func duplicateAsConflict() {
        let status = StorageUploadClient.effectiveStatus(
            httpStatus: 409,
            body: body(#"{"statusCode":"409","error":"Duplicate","message":"The resource already exists"}"#)
        )
        #expect(status == 409)
    }

    @Test("\"Already exists\" alone is enough to call it a duplicate")
    func duplicateByMessage() {
        let status = StorageUploadClient.effectiveStatus(
            httpStatus: 400,
            body: body(#"{"error":"Bad Request","message":"The resource already exists"}"#)
        )
        #expect(status == 409)
    }

    @Test("An expired token reads as 401 whatever the HTTP status")
    func expiredToken() {
        let asBadRequest = StorageUploadClient.effectiveStatus(
            httpStatus: 400,
            body: body(#"{"statusCode":"400","error":"Unauthorized","message":"jwt expired"}"#)
        )
        let asForbidden = StorageUploadClient.effectiveStatus(
            httpStatus: 403,
            body: body(#"{"statusCode":"403","error":"Unauthorized","message":"jwt expired"}"#)
        )
        #expect(asBadRequest == 401)
        #expect(asForbidden == 401)
    }

    @Test("A size refusal inside a 400 reads as 413")
    func payloadTooLarge() {
        let status = StorageUploadClient.effectiveStatus(
            httpStatus: 400,
            body: body(#"{"statusCode":"413","error":"Payload too large","message":"The object exceeded the maximum allowed size"}"#)
        )
        #expect(status == 413)
    }

    @Test("A policy refusal is not mistaken for an auth or duplicate problem")
    func policyRefusal() {
        let status = StorageUploadClient.effectiveStatus(
            httpStatus: 403,
            body: body(#"{"statusCode":"403","error":"Unauthorized","message":"new row violates row-level security policy"}"#)
        )
        #expect(status == 403)
    }

    @Test("A body that is not JSON leaves the HTTP status alone")
    func nonJSONBody() {
        #expect(StorageUploadClient.effectiveStatus(httpStatus: 502, body: body("Bad Gateway")) == 502)
        #expect(StorageUploadClient.effectiveStatus(httpStatus: 400, body: Data()) == 400)
    }

    @Test("The client cap sits under the 50 MB project upload limit")
    func uploadCapFitsTheServer() {
        #expect(VideoTranscoder.maxUploadBytes < 50 * 1024 * 1024)
    }
}

@Suite("Invite text")
struct InviteTextTests {

    @Test("The add-me line carries the @username")
    func lineCarriesHandle() {
        #expect(InviteLink.addMeLine(handle: "@sam") == "Add me on FrisFocus: @sam")
        #expect(InviteLink.addMeLine(handle: "sam") == "Add me on FrisFocus: @sam")
    }

    @Test("Without a username it falls back to the bare ask")
    func lineWithoutHandle() {
        #expect(InviteLink.addMeLine(handle: nil) == "Add me on FrisFocus")
        #expect(InviteLink.addMeLine(handle: "  ") == "Add me on FrisFocus")
        #expect(InviteLink.addMeLine(handle: "@") == "Add me on FrisFocus")
    }

    @Test("The full text is the line, then the link")
    func fullTextHasLineAndLink() {
        let text = InviteLink.shareText(handle: "@sam", userId: "usr_1")
        #expect(text.hasPrefix("Add me on FrisFocus: @sam\n"))
        #expect(text.contains("/functions/v1/invite?u=usr_1"))
    }
}
