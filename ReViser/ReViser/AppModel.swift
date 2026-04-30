//
//  AppModel.swift
//  ReViser
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

    struct DeletedSection: Identifiable, Equatable {
        let id: UUID
        let projectID: UUID
        let projectTitle: String
        let section: Section
        let originalIndex: Int
        let deletedAt: Date
    }

    var immersiveSpaceState = ImmersiveSpaceState.closed
    var isSectionsWindowOpen: Bool = false
    var noteMode: Bool = false
    var showSectionNumbersInWindows: Bool = false
    var elevateSectionWindowsForBulkOpen: Bool = false
    var sectionGraveyard: [DeletedSection] = []

    // Projects
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

    // Document importing state
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
        let didStartAccessingResource = url.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessingResource {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let type = try url.resourceValues(forKeys: [.contentTypeKey]).contentType
            if type == .plainText || url.pathExtension.lowercased() == "txt" {
                let text = try String(contentsOf: url, encoding: .utf8)
                importedText = text
                createOrUpdateProject(from: url, text: text)
                return
            }
            if url.pathExtension.lowercased() == "docx" {
                let result = try await extractDocxImportResult(url: url)
                importedText = result.text
                createOrUpdateProject(from: url, importResult: result)
                return
            }
            // Fallback: try to read as UTF-8 text
            let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            print("load in is", text)
            importedText = text
            createOrUpdateProject(from: url, text: text)
        } catch {
            print("Failed to load imported document from \(url.lastPathComponent): \(error)")
            importedText = ""
        }
    }

    private func createOrUpdateProject(from url: URL, importResult: DocxImportResult) {
        let initialSection = Section(
            id: UUID(),
            text: importResult.text,
            highlights: importResult.highlightRanges,
            boldStyles: importResult.boldRanges,
            italicStyles: importResult.italicRanges,
            underlineStyles: importResult.underlineRanges,
            strikethroughStyles: importResult.strikethroughRanges
        )
        updateProject(from: url, text: importResult.text, initialSection: initialSection)
    }

    private func createOrUpdateProject(from url: URL, text: String) {
        let initialSection = Section(id: UUID(), text: text)
        updateProject(from: url, text: text, initialSection: initialSection)
    }

    private func updateProject(from url: URL, text: String, initialSection: Section) {
        let baseTitle = url.deletingPathExtension().lastPathComponent
        let now = Date()

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
            projects[i].text = sections
                .map(\.text)
                .joined(separator: "")
            projects[i].lastModified = .now
        }
    }

    func previewText(for project: Project, limit: Int = 200) -> String {
        var collected = ""
        for section in project.sections {
            collected.append(section.text)
            if collected.count >= limit * 2 { break }
        }
        let source = collected.isEmpty ? project.text : collected
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "(Empty project)" }
        return String(trimmed.prefix(limit))
    }

    func moveSectionToGraveyard(projectID: UUID, section: Section, originalIndex: Int) {
        guard let project = projects.first(where: { $0.id == projectID }) else { return }

        let deleted = DeletedSection(
            id: UUID(),
            projectID: projectID,
            projectTitle: project.title,
            section: section,
            originalIndex: originalIndex,
            deletedAt: .now
        )
        sectionGraveyard.insert(deleted, at: 0)
    }

    func restoreSectionFromGraveyard(_ deletedID: UUID) {
        guard let graveyardIndex = sectionGraveyard.firstIndex(where: { $0.id == deletedID }) else { return }
        let deleted = sectionGraveyard[graveyardIndex]

        guard let projectIndex = projects.firstIndex(where: { $0.id == deleted.projectID }) else { return }

        let insertionIndex = min(max(deleted.originalIndex, 0), projects[projectIndex].sections.count)
        projects[projectIndex].sections.insert(deleted.section, at: insertionIndex)
        projects[projectIndex].lastModified = .now
        sectionGraveyard.remove(at: graveyardIndex)
    }

    func removeFromGraveyardPermanently(_ deletedID: UUID) {
        sectionGraveyard.removeAll { $0.id == deletedID }
    }

    func deleteProject(_ projectID: UUID) {
        projects.removeAll { $0.id == projectID }
        sectionGraveyard.removeAll { $0.projectID == projectID }
    }

    /// Extracts text and inline style ranges from a .docx by unzipping and parsing word/document.xml.
    private func extractDocxImportResult(url: URL) async throws -> DocxImportResult {
        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            throw NSError(domain: "Docx", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to open DOCX archive: \(error.localizedDescription)"])
        }

        let mainPath = "word/document.xml"
        guard let entry = archive[mainPath] else {
            return DocxImportResult(text: "", boldRanges: [], italicRanges: [], underlineRanges: [], strikethroughRanges: [], highlightRanges: [])
        }

        var xmlData = Data()
        _ = try archive.extract(entry) { chunk in
            xmlData.append(chunk)
        }
        guard let xmlString = String(data: xmlData, encoding: .utf8) else {
            return DocxImportResult(text: "", boldRanges: [], italicRanges: [], underlineRanges: [], strikethroughRanges: [], highlightRanges: [])
        }

        return DocxFormatter().convertWithStyles(documentXML: xmlString)
    }

    
    func updateProjectText(id: UUID, text: String) {
        if let index = projects.firstIndex(where: { $0.id == id }) {
            projects[index].text = text
            if projects[index].sections.isEmpty {
                projects[index].sections = [Section(id: UUID(), text: text)]
            } else {
                projects[index].sections[0].text = text
            }
            projects[index].lastModified = .now
        }
    }
}

