import FeedbackKit
import SwiftUI

struct PostDetailView: View {
    let postId: String

    @EnvironmentObject private var env: AppEnvironment
    @EnvironmentObject private var auth: AuthStore

    @State private var vm: PostDetailViewModel?
    @State private var commentText = ""
    @State private var isShowingSignIn = false

    var body: some View {
        Group {
            if let vm {
                PostDetailContent(
                    vm: vm,
                    commentText: $commentText,
                    isShowingSignIn: $isShowingSignIn
                )
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Post")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingSignIn, onDismiss: {
            Task { await vm?.retryPendingAction() }
        }) {
            SignInSheet()
        }
        .task {
            let model = PostDetailViewModel(
                postId: postId,
                api: env.api,
                isSignedIn: { [auth] in auth.isSignedIn }
            )
            vm = model
            await model.load()
        }
        .onChange(of: vm?.needsSignIn) { _, needsSignIn in
            if needsSignIn == true {
                isShowingSignIn = true
            }
        }
    }
}

private struct PostDetailContent: View {
    @ObservedObject var vm: PostDetailViewModel
    @Binding var commentText: String
    @Binding var isShowingSignIn: Bool

    var body: some View {
        List {
            if vm.isLoading && vm.post == nil {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowSeparator(.hidden)
            } else if let error = vm.errorMessage, vm.post == nil {
                ContentUnavailableView(
                    "Couldn't Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
                .listRowSeparator(.hidden)
            } else if let post = vm.post {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(post.title)
                            .font(.headline)

                        if !post.content.isEmpty {
                            Text(post.content)
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            Task { await vm.toggleVote() }
                        } label: {
                            Label(
                                "\(post.voteCount) vote\(post.voteCount == 1 ? "" : "s")",
                                systemImage: post.hasVoted ? "arrowtriangle.up.fill" : "arrowtriangle.up"
                            )
                            .foregroundStyle(post.hasVoted ? .blue : .primary)
                        }
                        .buttonStyle(.borderless)

                        if let error = vm.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section("Comments") {
                    HStack(alignment: .top) {
                        TextField("Add a comment…", text: $commentText, axis: .vertical)
                            .lineLimit(3...6)

                        Button {
                            let text = commentText
                            commentText = ""
                            Task { await vm.addComment(text) }
                        } label: {
                            Image(systemName: "paperplane.fill")
                        }
                        .buttonStyle(.borderless)
                        .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    if vm.comments.isEmpty && !vm.isLoading {
                        Text("No comments yet.")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(vm.comments) { comment in
                            CommentRowView(comment: comment)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            await vm.load()
        }
    }
}

private struct CommentRowView: View {
    let comment: Comment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(comment.authorName)
                    .font(.caption.bold())
                Spacer()
                Text(comment.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(comment.content)
                .font(.subheadline)

            if !comment.replies.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(comment.replies) { reply in
                        CommentRowView(comment: reply)
                            .padding(.leading, 16)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }
}
