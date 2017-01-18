//
//  SwipeTableViewController.swift
//  sample
//
//  Created by satoshi on 10/8/15.
//  Copyright © 2015 Satoshi Nakajima. All rights reserved.
//

#if os(OSX) // WARNING: OSX support is not done yet
import Cocoa
#else
import UIKit
#endif

private func MyLog(_ text:String, level:Int = 0) {
    let s_verbosLevel = 0
    if level <= s_verbosLevel {
        NSLog(text)
    }
}

//
// SwipeTableViewController is the "viewer" of documents with type "net.swipe.list"
//
class SwipeTableViewController: UIViewController, UITableViewDelegate, UITableViewDataSource, SwipeDocumentViewer {
    private var document:[String:Any]?
    private var sections = [[String:Any]]()
    //private var items = [[String:Any]]()
    private var url:URL?
    private var langId = "en"
    private weak var delegate:SwipeDocumentViewerDelegate?
    private var prefetching = true
    @IBOutlet private var tableView:UITableView!
    @IBOutlet private var imageView:UIImageView?

    // Returns the list of URLs of required resouces for this element (including children)
    private lazy var resourceURLs:[URL:String] = {
        var urls = [URL:String]()
        for section in self.sections {
            guard let items = section["items"] as? [[String:Any]] else {
                continue
            }
            for item in items {
                if let icon = item["icon"] as? String,
                    let url = URL.url(icon, baseURL: self.url) {
                    urls[url] = "" // no prefix
                }
            }
        }
        return urls
    }()

    lazy var prefetcher:SwipePrefetcher = {
        return SwipePrefetcher(urls:self.resourceURLs)
    }()
        
    // <SwipeDocumentViewer> method
    func loadDocument(_ document:[String:Any], size:CGSize, url:URL?, state:[String:Any]?, callback:@escaping (Float, NSError?)->(Void)) throws {
        self.document = document
        self.url = url
        if let languages = languages(),
           let langId = SwipeParser.preferredLangId(in: languages) {
            self.langId = langId
        }
        if let sections = document["sections"] as? [[String:Any]] {
            self.sections = sections
        } else if let items = document["items"] as? [[String:Any]] {
            let section = [ "items":items ]
            sections.append(section as [String : Any])
        } else {
            throw SwipeError.invalidDocument
        }
        _ = self.view // Make sure the view and subviews (tableView) are loaded from xib.
        updateRowHeight()
        
        self.prefetcher.start { (completed:Bool, _:[URL], _:[NSError]) -> Void in
            if completed {
                MyLog("SWTable prefetch complete", level:1)
                self.prefetching = false
                self.tableView.reloadData()
            }
            callback(self.prefetcher.progress, nil)
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        if let imageView = self.imageView {
            let effectView = UIVisualEffectView(effect: UIBlurEffect(style: .light))
            effectView.frame = imageView.frame
            effectView.autoresizingMask = UIViewAutoresizing([.flexibleWidth, .flexibleHeight])
            imageView.addSubview(effectView)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        if let selectedIndexPath = tableView.indexPathForSelectedRow {
            tableView.deselectRow(at: selectedIndexPath, animated: true)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateRowHeight()
    }
    
    private func updateRowHeight() {
        let size = self.tableView.bounds.size
        if let value = document?["rowHeight"] as? CGFloat {
            self.tableView.rowHeight = value
        } else if let value = document?["rowHeight"] as? String {
            self.tableView.rowHeight = SwipeParser.parsePercent(value, full: size.height, defaultValue: self.tableView.rowHeight)
        }
    }
    
    // <SwipeDocumentViewer> method
    func documentTitle() -> String? {
        return document?["title"] as? String
    }
    
    // <SwipeDocumentViewer> method
    func setDelegate(_ delegate:SwipeDocumentViewerDelegate) {
        self.delegate = delegate
    }
    
    // <SwipeDocumentViewer> method
    func hideUI() -> Bool {
        return false
    }

    // <SwipeDocumentViewer> method
    func landscape() -> Bool {
        return false
    }

    // <SwipeDocumentViewer> method
    func becomeZombie() {
        // no op
    }

    // <SwipeDocumentViewer> method
    func saveState() -> [String:Any]? {
        return nil
    }

    // <SwipeDocumentViewer> method
    func languages() -> [[String:Any]]? {
        return document?["languages"] as? [[String:Any]]
    }
    
    // <SwipeDocumentViewer> method
    func reloadWithLanguageId(_ langID:String) {
        self.langId = langID
        tableView.reloadData()
    }
    
    func moveToPageAt(index:Int) {
        // no op
    }
    func pageIndex() -> Int? {
        return nil
    }
    func pageCount() -> Int? {
        return nil
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - Table view data source

    func numberOfSections(in tableView: UITableView) -> Int {
        // #warning Incomplete implementation, return the number of sections
        return prefetching ? 0 : self.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        let section = self.sections[section]
        guard let items = section["items"] as? [[String:Any]] else {
            return 0
        }
        return items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = self.sections[indexPath.section]
        guard let items = section["items"] as? [[String:Any]] else {
            return dequeueCell(style: .default)
        }
        let item = items[indexPath.row]
        let text = parseText(info: item, key: "text")
        let cell = dequeueCell(style: text == nil ? .default : .subtitle)

        // Configure the cell...
        if let title = parseText(info: item, key: "title") {
            cell.textLabel!.text = title
        } else if let url = item["url"] as? String {
            cell.textLabel!.text = url
        }
        if let text = text {
            cell.detailTextLabel!.text = text
        }
        if let icon = item["icon"] as? String,
            let url = URL.url(icon, baseURL: self.url),
            let urlLocal = self.prefetcher.map(url),
            let image = UIImage(contentsOfFile: urlLocal.path) {
            cell.imageView?.image = image
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = self.sections[indexPath.section]
        guard let items = section["items"] as? [[String:Any]] else {
            return
        }
        let item = items[indexPath.row]
        if let urlString = item["url"] as? String,
           let url = URL.url(urlString, baseURL: self.url) {
            self.delegate?.browseTo(url)
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        let section = self.sections[section]
        return parseText(info: section, key: "title")
    }
    
    private static let cellIdentifiers = [UITableViewCellStyle.default: "default", .subtitle: "subtitle"] // value1 and value2 styles are not supported yet.
    
    private func dequeueCell(style: UITableViewCellStyle) -> UITableViewCell {
        let identifier = SwipeTableViewController.cellIdentifiers[style]!
        if let cell = tableView.dequeueReusableCell(withIdentifier: identifier) {
            cell.textLabel?.text = nil
            cell.detailTextLabel?.text = nil
            cell.imageView?.image = nil
            return cell
        } else {
            return UITableViewCell(style: style, reuseIdentifier: identifier)
        }
    }
    
    private func parseText(info: [String:Any], key:String) -> String? {
        guard let value = info[key] else {
            return nil
        }
        if let text = value as? String {
            return text
        }
        guard let params = value as? [String:Any] else {
            return nil
        }
        if let key = params["ref"] as? String,
           let strings = document?["strings"] as? [String:Any],
           let texts = strings[key] as? [String:Any],
           let text = SwipeParser.localizedString(texts, langId: langId) {
            return text
        }
        return SwipeParser.localizedString(params, langId: langId)
    }

    func tapped() {
        self.delegate?.tapped()
    }
    
    /*
    // Override to support conditional editing of the table view.
    override func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {
        if editingStyle == .Delete {
            // Delete the row from the data source
            tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Fade)
        } else if editingStyle == .Insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(tableView: UITableView, moveRowAtIndexPath fromIndexPath: NSIndexPath, toIndexPath: NSIndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(tableView: UITableView, canMoveRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
