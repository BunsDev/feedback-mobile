import Foundation

@MainActor
public final class PostDetailViewModel: ObservableObject {
    @Published public private(set) var post: PostDetail?
    @Published public private(set) var comments: [Comment] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public var needsSignIn = false

    private let postId: String
    private let api: FeedbackAPI
    private let isSignedIn: () -> Bool

    // An action the user attempted while signed out, replayed once they sign in.
    private enum PendingAction {
        case vote
        case comment(String)
    }
    private var pendingAction: PendingAction?
    // True while replaying a pending action after sign-in, used to avoid an
    // infinite sign-in loop if the write still fails as unauthenticated.
    private var isReplaying = false

    public init(postId: String, api: FeedbackAPI, isSignedIn: @escaping () -> Bool) {
        self.postId = postId
        self.api = api
        self.isSignedIn = isSignedIn
    }

    /// Replays the action that triggered a sign-in prompt, to be called after the
    /// sign-in sheet dismisses. If the user is still signed out (cancelled), the
    /// pending action is cleared so it never fires unexpectedly later.
    public func retryPendingAction() async {
        guard isSignedIn(), let action = pendingAction else { pendingAction = nil; return }
        pendingAction = nil
        isReplaying = true
        switch action {
        case .vote: await toggleVote()
        case .comment(let text): await addComment(text)
        }
        isReplaying = false
    }

    // A write rejected as unauthorized (the server may answer 404 instead of 401
    // for an invalid token). On the first failure, prompt sign-in and remember
    // the action to replay. If it fails again right after signing in, surface an
    // error instead of re-prompting, so the sign-in sheet can't loop forever.
    private func handleWriteAuthFailure(_ action: PendingAction) {
        if isReplaying {
            errorMessage = "Couldn't complete that. Please try again in a moment."
        } else {
            pendingAction = action
            needsSignIn = true
        }
    }

    public func load() async {
        isLoading = true; errorMessage = nil
        do {
            async let p = api.getPost(id: postId)
            async let c = api.listComments(postId: postId)
            post = try await p
            comments = try await c
        } catch {
            errorMessage = FeedViewModel.message(for: error)
        }
        isLoading = false
    }

    public func toggleVote() async {
        needsSignIn = false
        errorMessage = nil
        guard isSignedIn() else { pendingAction = .vote; needsSignIn = true; return }
        do {
            let result = try await api.vote(postId: postId)
            pendingAction = nil
            if let current = post {
                post = PostDetail(
                    id: current.id,
                    title: current.title,
                    content: current.content,
                    voteCount: result.voteCount,
                    statusId: current.statusId,
                    boardId: current.boardId,
                    createdAt: current.createdAt,
                    hasVoted: result.voted
                )
            }
        } catch APIError.unauthorized, APIError.notFound {
            handleWriteAuthFailure(.vote)
        } catch {
            errorMessage = FeedViewModel.message(for: error)
        }
    }

    public func addComment(_ text: String) async {
        needsSignIn = false
        errorMessage = nil
        guard isSignedIn() else { pendingAction = .comment(text); needsSignIn = true; return }
        do {
            let comment = try await api.addComment(postId: postId, content: text, parentId: nil)
            pendingAction = nil
            comments.insert(comment, at: 0)
        } catch APIError.unauthorized, APIError.notFound {
            handleWriteAuthFailure(.comment(text))
        } catch {
            errorMessage = FeedViewModel.message(for: error)
        }
    }
}
