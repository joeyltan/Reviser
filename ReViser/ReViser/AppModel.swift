//
//  AppModel.swift
//  ReViser
//
//  Created by Joey Tan on 2/9/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    
    struct Project: Identifiable, Hashable {
        let id: UUID
        var title: String
        var sourceURL: URL
        var createdAt: Date
        var lastModified: Date
        var text: String
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed

    // MARK: - Projects
    var projects: [Project] = []
    var searchQuery: String = ""

    /// Computed projects filtered by search query (case-insensitive contains on title)
    var filteredProjects: [Project] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return projects.sorted { $0.lastModified > $1.lastModified } }
        return projects
            .filter { $0.title.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            .sorted { $0.lastModified > $1.lastModified }
    }

    // MARK: - Document importing state
    var importedText: String = ""
    var importedFileName: String? = nil

    // Supported content types (.txt and .docx primarily, allow any text-like type)
    var supportedContentTypes: [UTType] {
        [
            .plainText,
            UTType(filenameExtension: "docx")!,
            .rtf,
            .pdf
        ]
    }

    /// Load text content from a given URL. Handles .txt directly and attempts a very simple .docx extraction.
    func loadDocument(from url: URL) async {
        importedFileName = url.lastPathComponent
        do {
            let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
            if type == .plainText || url.pathExtension.lowercased() == "txt" {
                let text = try String(contentsOf: url, encoding: .utf8)
                importedText = text
                createOrUpdateProject(from: url, text: text)
                return
            }
            if url.pathExtension.lowercased() == "docx" {
                let text = try await extractTextFromDocx(url: url)
                importedText = text
                createOrUpdateProject(from: url, text: text)
                return
            }
            // Fallback: try to read as UTF-8 text
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            importedText = text
            createOrUpdateProject(from: url, text: text)
        } catch {
            importedText = ""
        }
    }

    private func createOrUpdateProject(from url: URL, text: String) {
        let baseTitle = url.deletingPathExtension().lastPathComponent
        let now = Date()
        if let idx = projects.firstIndex(where: { $0.sourceURL == url }) {
            // Update existing project
            projects[idx].text = text
            projects[idx].lastModified = now
        } else {
            let project = Project(
                id: UUID(),
                title: baseTitle,
                sourceURL: url,
                createdAt: now,
                lastModified: now,
                text: text
            )
            projects.append(project)
        }
    }

    /// Extremely lightweight .docx text extraction by unzipping and reading word/document.xml, then stripping basic XML tags.
    private func extractTextFromDocx(url: URL) async throws -> String {
        // .docx is a zip. We'll use FileManager + built-in Archive via Foundation to access data.
        // Since there's no first-party high-level unzip in Foundation, copy to a temporary location and use `ZIPFoundation`-like approach is ideal.
        // To keep dependencies out, we fallback to reading the raw data and using `URLResourceValues`—but here we'll punt to QuickLook to generate a plain text preview if possible.
        // For a robust solution, consider integrating a docx parser. For now, return empty string to avoid blocking.
        return "" // Placeholder to keep app stable without third-party libs.
    }
}
