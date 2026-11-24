// XLSXExport.swift：把一個行程匯出成 Excel 檔（.xlsx）。
//
// Excel 檔其實是一個 zip 壓縮檔，裡面放幾個固定格式的 XML 文字檔。
// 這裡自己寫出那些 XML，再用 macOS 內建的 zip 指令（/usr/bin/zip）打包，不需要另外安裝任何東西。
//
// 欄位和作者的花費表類似：項次、日期、時間、項目（店名-品項）、付款方式、卡號前 6 碼、原幣金額、分類、待確認、備註。
// 需要確認的那一筆，「項目」用紅字。日期、時間、金額寫成 Excel 認得的數字，可以排序和加總。
// 匯出一律寫成新檔；檔名重複時自動加上編號，不會覆蓋已有的檔案。

import Foundation

enum XLSXExport {
    enum ExportError: Error, CustomStringConvertible {
        case zipFailed(String)
        var description: String {
            switch self { case .zipFailed(let message): return "壓縮成 Excel 檔失敗：\(message)" }
        }
    }

    /// 匯出到 url（如果已經有同名檔案，會自動改名），回傳實際寫入的位置。
    @discardableResult
    static func export(_ trip: Trip, to url: URL) throws -> URL {
        let target = LedgerStore.uniqueURL(url)
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("tripledger-xlsx-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: work) }

        let files: [(String, String)] = [
            ("[Content_Types].xml", contentTypes),
            ("_rels/.rels", rootRels),
            ("xl/workbook.xml", workbook),
            ("xl/_rels/workbook.xml.rels", workbookRels),
            ("xl/styles.xml", styles),
            ("xl/worksheets/sheet1.xml", sheet(for: trip)),
        ]
        for (path, content) in files {
            let fileURL = work.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: fileURL)
        }

        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = work
        zip.arguments = ["-X", "-r", "-q", target.path, "[Content_Types].xml", "_rels", "xl"]
        let pipe = Pipe()
        zip.standardError = pipe
        try zip.run()
        zip.waitUntilExit()
        if zip.terminationStatus != 0 {
            let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ExportError.zipFailed(message)
        }
        return target
    }

    // MARK: - 工作表內容

    static let headers = ["項次", "日期", "時間", "項目", "付款方式", "卡號前6碼", "原幣金額", "分類", "待確認", "備註"]
    static let widths = [6, 8, 7, 34, 10, 10, 12, 6, 24, 20]

    static func sheet(for trip: Trip) -> String {
        var rows: [String] = []
        let headerCells = headers.enumerated().map { i, h in inlineCell(col: i, row: 1, text: h, style: 1) }
        rows.append("<row r=\"1\">" + headerCells.joined() + "</row>")

        for (index, r) in trip.sortedReceipts.enumerated() {
            let n = index + 2
            var cells: [String] = []
            cells.append(numberCell(col: 0, row: n, value: Double(index + 1), style: 0))
            if let serial = r.date.flatMap(excelDate) { cells.append(numberCell(col: 1, row: n, value: serial, style: 2)) }
            if let fraction = r.time.flatMap(excelTime) { cells.append(numberCell(col: 2, row: n, value: fraction, style: 3)) }
            cells.append(inlineCell(col: 3, row: n, text: r.title, style: r.needsReview ? 5 : 0))
            cells.append(inlineCell(col: 4, row: n, text: PayMethod.label(r.pay), style: 0))
            if let card = r.cardPrefix { cells.append(inlineCell(col: 5, row: n, text: card, style: 0)) }
            if let amount = r.amount { cells.append(numberCell(col: 6, row: n, value: Double(amount), style: 4)) }
            if let category = r.category { cells.append(inlineCell(col: 7, row: n, text: category, style: 0)) }
            if r.needsReview { cells.append(inlineCell(col: 8, row: n, text: r.problems.joined(separator: "、"), style: 5)) }
            if !r.note.isEmpty { cells.append(inlineCell(col: 9, row: n, text: r.note, style: 0)) }
            rows.append("<row r=\"\(n)\">" + cells.joined() + "</row>")
        }

        let cols = widths.enumerated().map { i, w in "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(w)\" customWidth=\"1\"/>" }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
        <sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>\
        <cols>\(cols.joined())</cols>\
        <sheetData>\(rows.joined())</sheetData>\
        </worksheet>
        """
    }

    /// A、B、C… 欄名。
    static func columnName(_ index: Int) -> String {
        var n = index
        var name = ""
        repeat {
            name = String(UnicodeScalar(UInt8(65 + n % 26))) + name
            n = n / 26 - 1
        } while n >= 0
        return name
    }

    static func inlineCell(col: Int, row: Int, text: String, style: Int) -> String {
        "<c r=\"\(columnName(col))\(row)\" t=\"inlineStr\" s=\"\(style)\"><is><t xml:space=\"preserve\">\(escape(text))</t></is></c>"
    }

    static func numberCell(col: Int, row: Int, value: Double, style: Int) -> String {
        "<c r=\"\(columnName(col))\(row)\" s=\"\(style)\"><v>\(value)</v></c>"
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// yyyy-MM-dd → Excel 的日期數字（從 1899-12-30 算起的天數）。
    static func excelDate(_ text: String) -> Double? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])),
              let origin = calendar.date(from: DateComponents(year: 1899, month: 12, day: 30)) else { return nil }
        return (date.timeIntervalSince(origin) / 86400).rounded()
    }

    /// HH:mm → 一天中的比例（Excel 的時間格式）。
    static func excelTime(_ text: String) -> Double? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Double(parts[0] * 60 + parts[1]) / 1440.0
    }

    // MARK: - 固定的檔案

    static let contentTypes = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
    <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
    <Default Extension="xml" ContentType="application/xml"/>\
    <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
    <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>\
    <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
    </Types>
    """

    static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
    </Relationships>
    """

    static let workbook = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
    <sheets><sheet name="花費表" sheetId="1" r:id="rId1"/></sheets>\
    </workbook>
    """

    static let workbookRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>\
    <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>\
    </Relationships>
    """

    /// 樣式：0 一般、1 標題粗體、2 日期 m/d、3 時間 h:mm、4 金額 #,##0、5 紅字
    static let styles = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
    <numFmts count="3"><numFmt numFmtId="164" formatCode="m/d"/><numFmt numFmtId="165" formatCode="h:mm"/><numFmt numFmtId="166" formatCode="#,##0"/></numFmts>\
    <fonts count="3"><font><sz val="12"/><name val="Arial"/></font><font><b/><sz val="12"/><name val="Arial"/></font><font><sz val="12"/><color rgb="FFFF0000"/><name val="Arial"/></font></fonts>\
    <fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills>\
    <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>\
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
    <cellXfs count="6">\
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>\
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>\
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="166" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>\
    <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>\
    </cellXfs>\
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>\
    </styleSheet>
    """
}
