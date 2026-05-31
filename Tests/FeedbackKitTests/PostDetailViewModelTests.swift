@testable import FeedbackKit
import XCTest

/// Always rejects votes with notFound (the live server answers 404 instead of
/// 401 for an invalid token).
private final class NotFoundVoteAPI: MockFeedbackAPI {
    override func vote(postId: String) async throws -> VoteResult { throw APIError.notFound }
}

/// Always rejects votes as unauthorized — used to verify the replay can't loop.
private final class AlwaysUnauthorizedVoteAPI: MockFeedbackAPI {
    override func vote(postId: String) async throws -> VoteResult { throw APIError.unauthorized }
}

@MainActor
final class PostDetailViewModelTests: XCTestCase {
    func testLoadFetchesPostAndComments() async {
        let api = MockFeedbackAPI()
        let vm = PostDetailViewModel(postId: "post_1", api: api, isSignedIn: { true })
        await vm.load()
        XCTAssertEqual(vm.post?.id, "post_1")
        XCTAssertNotNil(vm.comments)
    }

    func testVoteUpdatesCountWhenSignedIn() async {
        let api = MockFeedbackAPI()
        api.voteResult = VoteResult(voted: true, voteCount: 9)
        let vm = PostDetailViewModel(postId: "post_1", api: api, isSignedIn: { true })
        await vm.load()
        await vm.toggleVote()
        XCTAssertEqual(vm.post?.voteCount, 9)
        XCTAssertEqual(vm.post?.hasVoted, true)
        XCTAssertFalse(vm.needsSignIn)
    }

    func testVoteWhenSignedOutRequestsSignIn() async {
        let vm = PostDetailViewModel(postId: "post_1", api: MockFeedbackAPI(), isSignedIn: { false })
        await vm.load()
        await vm.toggleVote()
        XCTAssertTrue(vm.needsSignIn)
    }

    func testVoteResetsNeedsSignInBeforeRepeatedSignedOutAttempts() async {
        let vm = PostDetailViewModel(postId: "post_1", api: MockFeedbackAPI(), isSignedIn: { false })
        await vm.load()
        await vm.toggleVote()
        XCTAssertTrue(vm.needsSignIn)
        vm.needsSignIn = false

        await vm.toggleVote()

        XCTAssertTrue(vm.needsSignIn)
    }

    func testAddCommentResetsNeedsSignInBeforeRepeatedSignedOutAttempts() async {
        let vm = PostDetailViewModel(postId: "post_1", api: MockFeedbackAPI(), isSignedIn: { false })
        await vm.load()
        await vm.addComment("hello")
        XCTAssertTrue(vm.needsSignIn)
        vm.needsSignIn = false

        await vm.addComment("hello")

        XCTAssertTrue(vm.needsSignIn)
    }

    // A vote attempted while signed out must replay after the user signs in,
    // instead of being silently dropped when the sign-in sheet dismisses.
    func testPendingVoteReplaysAfterSignIn() async {
        var signedIn = false
        let api = MockFeedbackAPI()
        api.voteResult = VoteResult(voted: true, voteCount: 7)
        let vm = PostDetailViewModel(postId: "post_1", api: api, isSignedIn: { signedIn })
        await vm.load()

        await vm.toggleVote()
        XCTAssertTrue(vm.needsSignIn)
        XCTAssertNil(api.votedPostId, "must not vote while signed out")

        signedIn = true
        await vm.retryPendingAction()

        XCTAssertEqual(api.votedPostId, "post_1", "pending vote should replay after sign-in")
        XCTAssertEqual(vm.post?.voteCount, 7)
        XCTAssertEqual(vm.post?.hasVoted, true)
        XCTAssertFalse(vm.needsSignIn)
    }

    // Likewise a comment composed while signed out should post after sign-in.
    func testPendingCommentReplaysAfterSignIn() async {
        var signedIn = false
        let api = MockFeedbackAPI()
        let vm = PostDetailViewModel(postId: "post_1", api: api, isSignedIn: { signedIn })
        await vm.load()

        await vm.addComment("great idea")
        XCTAssertTrue(vm.needsSignIn)
        XCTAssertNil(api.addedComment, "must not post while signed out")

        signedIn = true
        await vm.retryPendingAction()

        XCTAssertEqual(api.addedComment?.content, "great idea")
        XCTAssertFalse(vm.needsSignIn)
    }

    // Cancelling sign-in (still signed out) must clear the pending action so it
    // doesn't fire unexpectedly later.
    func testRetryWithoutSignInClearsPendingAction() async {
        var signedIn = false
        let api = MockFeedbackAPI()
        let vm = PostDetailViewModel(postId: "post_1", api: api, isSignedIn: { signedIn })
        await vm.load()
        await vm.toggleVote()

        // User cancelled the sheet — retry runs but is still signed out.
        await vm.retryPendingAction()
        XCTAssertNil(api.votedPostId)

        // Later sign-in alone must not resurrect the cancelled vote.
        signedIn = true
        await vm.retryPendingAction()
        XCTAssertNil(api.votedPostId, "cancelled action must not replay")
    }

    // The live server answers 404 (not 401) for a write with an invalid token,
    // so a notFound on a vote should prompt re-auth just like unauthorized.
    func testVoteNotFoundPromptsReauth() async {
        let vm = PostDetailViewModel(postId: "post_1", api: NotFoundVoteAPI(), isSignedIn: { true })
        await vm.load()
        await vm.toggleVote()
        XCTAssertTrue(vm.needsSignIn, "a 404 on a write should prompt sign-in")
    }

    // If the replay after sign-in still fails, surface an error rather than
    // re-prompting sign-in forever.
    func testFailedReplaySurfacesErrorWithoutLooping() async {
        let vm = PostDetailViewModel(postId: "post_1", api: AlwaysUnauthorizedVoteAPI(), isSignedIn: { true })
        await vm.load()

        await vm.toggleVote()
        XCTAssertTrue(vm.needsSignIn)

        // Sign-in sheet dismissed; replay runs but the write still fails.
        vm.needsSignIn = false
        await vm.retryPendingAction()

        XCTAssertFalse(vm.needsSignIn, "must not re-prompt sign-in (no loop)")
        XCTAssertNotNil(vm.errorMessage, "a failed replay should surface an error")
    }
}
