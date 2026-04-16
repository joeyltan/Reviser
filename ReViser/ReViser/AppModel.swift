//
//  AppModel.swift
//  ReViser
//
//  Created by Joey Tan on 2/9/26.
//

import SwiftUI
import UniformTypeIdentifiers
import Foundation
import ZIPFoundation

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
    
    struct Project: Identifiable {
        let id: UUID
        var title: String
        var sourceURL: URL
        var createdAt: Date
        var lastModified: Date
        var text: String
        var sections: [Section]
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
    var isSectionsWindowOpen: Bool = false

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
                print("extracting text from docx", text)
                importedText = text
                createOrUpdateProject(from: url, text: text)
                return
            }
            // Fallback: try to read as UTF-8 text
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            print("load in is", text)
            importedText = text
            createOrUpdateProject(from: url, text: text)
        } catch {
            importedText = ""
        }
    }

    private func createOrUpdateProject(from url: URL, text: String) {
        let baseTitle = url.deletingPathExtension().lastPathComponent
        let now = Date()

        // Create initial section
        let initialSection = Section(id: UUID(), text: text)

        if let idx = projects.firstIndex(where: { $0.sourceURL == url }) {
            // Update existing project
            projects[idx].sections = [initialSection]
            projects[idx].lastModified = now
        } else {
            // New project
            let project = Project(
                id: UUID(),
                title: baseTitle,
                sourceURL: url,
                createdAt: now,
                lastModified: now,
                text: text,
                sections: [initialSection]
            )
            projects.append(project)
        }
    }
    
    func updateProjectSections(id: UUID, sections: [Section]) {
        if let i = projects.firstIndex(where: { $0.id == id }) {
            projects[i].sections = sections
            projects[i].lastModified = .now
        }
    }

    /// Extremely lightweight .docx text extraction by unzipping and reading word/document.xml, then stripping basic XML tags.
    private func extractTextFromDocx(url: URL) async throws -> String {
        // Open the .docx as a ZIP archive
        // ok this is not loaded in quite right, because it already has the repetition here
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw NSError(domain: "Docx", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to open DOCX archive: \(error.localizedDescription)"])
        }

        // Only extract the main document body to avoid repeated header/footer content.
        let mainPath = "word/document.xml"
        guard let entry = archive[mainPath] else {
            return ""
        }

        var xmlData = Data()
        _ = try archive.extract(entry) { chunk in
            xmlData.append(chunk)
        }
        guard let xmlString = String(data: xmlData, encoding: .utf8) else {
            return ""
        }

        return DocxFormatter().convert(documentXML: xmlString)
    }

    
    func updateProjectText(id: UUID, text: String) {
        // If AppModel is a class with a mutable array:
        if let index = projects.firstIndex(where: { $0.id == id }) {
            projects[index].text = text
            projects[index].lastModified = .now
            // If you persist to disk, trigger save here
            // saveProjects()
        }
    }
}

