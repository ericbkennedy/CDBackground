//
//  ViewController.swift
//  simpleCoreData
//
//  Created by Eric Kennedy on 8/15/23.
//

import CoreData
import UIKit

class ViewController: UITableViewController, UISearchResultsUpdating, UISearchBarDelegate {

    let searchController = UISearchController(searchResultsController: nil)
    var container: NSPersistentContainer!
    var searchPredicate: NSPredicate?
    var items = [NSManagedObject]()
    var showCommits = true

    override func viewDidLoad() {
        super.viewDidLoad()

        if let selectedTabTitle = tabBarController?.tabBar.selectedItem?.title {
            print("tabBarController?.tabBar.selectedItem?.title =", selectedTabTitle)
        }

        if tabBarController?.selectedIndex == 1 { // Note tabBarItem.tag and tabBar.badgeName appear to be nil
            showCommits = false
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Filter", style: .plain, target: self, action: #selector(changeFilter))

        container = NSPersistentContainer(name: "simpleModel")
        container.loadPersistentStores { storeDescription, error in
            // mergePolicy allows in memory object to overwrite prior Store value
            self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            if let error {
                print("Unresolved error \(error)")
            }
        }

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Search by commit message or author"
//        searchController.searchBar.scopeButtonTitles = ["Name", "Capital"]

        searchController.searchBar.delegate = self
        searchController.scopeBarActivation = .onTextEntry

        navigationItem.searchController = searchController
        definesPresentationContext = true


        NotificationCenter.default.addObserver(self,
                                       selector: #selector(managedObjectContextDidSave),
                                       name: .NSManagedObjectContextDidSave,
                                       object: nil) // Note: this needs to be either nil or taskContext

        let taskContext = newTaskContext()
        Task {
            let newestCommitDate = "" // getNewestCommitDate()
            print("newestCommitDate=", newestCommitDate)
            if let githubCommits = await GithubService().fetchCommits(newestCommitDate: newestCommitDate) {
                print(githubCommits.count, " from API after \(newestCommitDate)")

                await taskContext.perform {
                    for githubCommit in githubCommits {
                        self.configure(taskContext: taskContext, using: githubCommit)
                    }

                    self.saveContext(context: taskContext)
                }
            } else {
                print("no commits processed")
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        loadSavedData()
    }

    func updateSearchResults(for searchController: UISearchController) {
        if let searchText = searchController.searchBar.text, searchText.count > 0 {
            if showCommits {
                searchPredicate = NSPredicate(format: "message CONTAINS[c] %@", searchText) // [c] is predicate-speak for "case-insensitive"

            } else {
                searchPredicate = NSPredicate(format: "name CONTAINS[c] %@", searchText)
            }
        } else {
            searchPredicate = nil
        }
        loadSavedData()
    }

    // MARK: UISearchBarDelegate
    func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
        searchPredicate = nil
        loadSavedData()
    }

    // limit text length to 5 characters, see https://stackoverflow.com/questions/433337/
    func searchBar(_ searchBar: UISearchBar, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool // called before text changes
    {
        let currentCharacterCount = searchBar.text?.count ?? 0
        if range.length + range.location > currentCharacterCount {
            // Return false if the attempted replacement length > currentCharacterCount.
            // This occurs after a long string is pasted in but this method prevents the paste,
            // followed by a shake to undo.
            // The undo buffer has text that isn't in searchBar.text? so the range will be out of bounds
            return false
        }
        let newLength = currentCharacterCount + text.count - range.length
        return newLength <= 5
    }

    @objc func managedObjectContextDidSave(notification: NSNotification) {
        print("managedObjectContextDidSave")
        guard let userInfo = notification.userInfo else { return }
        dump(userInfo)
        if let inserts = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject>, inserts.count > 0 {
            print("--- INSERTS ---")
            print(inserts)
            print("+++++++++++++++")
        }
        // other keys: let updates = userInfo[NSUpdatedObjectsKey], let deletes = userInfo[NSDeletedObjectsKey]

        DispatchQueue.main.async { [weak self] in
            print("dispatch to main thread")
            self?.loadSavedData()
        }
    }

    func configure(taskContext: NSManagedObjectContext, using githubCommit: GithubCommit) {
        let commit = Commit(context: taskContext)

        commit.sha = githubCommit.sha
        commit.url = githubCommit.url
        commit.message = githubCommit.commit.message

        let formatter = ISO8601DateFormatter()
        commit.date = formatter.date(from: githubCommit.commit.author.date) ?? Date()

        var commitAuthor: Author!

        // see if this author exists already
        let authorRequest = Author.fetchRequest()
        authorRequest.predicate = NSPredicate(format: "name == %@", githubCommit.commit.author.name)

        if let authors = try? taskContext.fetch(authorRequest) {
            if authors.count > 0 {
                // we have this author already
                commitAuthor = authors[0]
            }
        }

        if commitAuthor == nil {
            // we didn't find a saved author - create a new one!
            let author = Author(context: taskContext)
            author.name = githubCommit.commit.author.name
            author.email = githubCommit.commit.author.email
            author.date = commit.date // already formatted
            commitAuthor = author
        }

        // use the author, either saved or new
        commit.author = commitAuthor
        // have the caller call save on the taskContext to avoid multiple dispatches to reload the tableview
    }

    @objc func changeFilter() {
           let ac = UIAlertController(title: "Filter items...", message: nil, preferredStyle: .actionSheet)

           ac.addAction(UIAlertAction(title: "Show only fixes", style: .default) { [unowned self] _ in
               self.searchPredicate = NSPredicate(format: "message CONTAINS[c] 'fix'") // [c] is predicate-speak for "case-insensitive"
               self.loadSavedData()
           })

           ac.addAction(UIAlertAction(title: "Ignore Pull Requests", style: .default) { [unowned self] _ in
               self.searchPredicate = NSPredicate(format: "NOT message BEGINSWITH 'Merge pull request'")
               self.loadSavedData()
           })

           ac.addAction(UIAlertAction(title: "Show only recent", style: .default) { [unowned self] _ in
               let twelveHoursAgo = Date().addingTimeInterval(-43200)
               self.searchPredicate = NSPredicate(format: "date > %@", twelveHoursAgo as NSDate)
               self.loadSavedData()
           })

           ac.addAction(UIAlertAction(title: "Show all commits", style: .default) { [unowned self] _ in
               self.searchPredicate = nil
               self.loadSavedData()
           })

           ac.addAction(UIAlertAction(title: "Show only Ben Barham commits", style: .default) { [unowned self] _ in
               self.searchPredicate = NSPredicate(format: "author.name == 'Ben Barham'")
               self.loadSavedData()
           })

           ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
           present(ac, animated: true)
       }

        func loadSavedData() {
            if showCommits {
                fetchData(entity: Commit.self)
            } else {
                fetchData(entity: Author.self)
            }
       }

        func fetchData<T: NSManagedObject>(entity: T.Type) {
            let fetchRequest = T.fetchRequest()
            let sort = NSSortDescriptor(key: "date", ascending: false)
            fetchRequest.sortDescriptors = [sort]
            do {
                fetchRequest.predicate = searchPredicate
                let rows = try container.viewContext.fetch(fetchRequest)

                print("Got \(rows.count) from CoreData")

                items.removeAll(keepingCapacity: true)
                for row in rows {
                    if let entity = row as? T {
                        items.append(entity)
                    } else {
                        print("could not convert type")
                    }
                }
                tableView.reloadData()
            } catch {
                print("error occurred \(error)")
            }
        }

       override func numberOfSections(in tableView: UITableView) -> Int {
           return 1
       }

       override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
           return items.count
       }

       override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
           let index = indexPath.row

           let cellID = showCommits ? "Commit" : "Author"

           let cell = tableView.dequeueReusableCell(withIdentifier: cellID, for: indexPath)
           var config = cell.defaultContentConfiguration()

           if index < items.count {
               let item = items[index]
               if let commit = item as? Commit {
                   config.text = commit.message
                   config.secondaryText = "By \(commit.author.name) on \(commit.date.description)"
               } else if let author = item as? Author {
                   config.text = author.name
                   config.secondaryText = author.email
               }

//               config.text = item.title
//               config.secondaryText = item.subtitle
           }
           cell.contentConfiguration = config
           return cell
       }

       override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
           if let vc = storyboard?.instantiateViewController(withIdentifier: "Detail") as? DetailViewController {
               vc.detailItem = items[indexPath.row]
               navigationController?.pushViewController(vc, animated: true)
           }
       }

       override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
           if editingStyle == .delete {
               let item = items[indexPath.row]
               container.viewContext.delete(item)
               items.remove(at: indexPath.row)
               tableView.deleteRows(at: [indexPath], with: .fade)

               saveContext(context: container.viewContext)
           }
       }

    func saveContext(context: NSManagedObjectContext) {
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                print("An error has occurred while saving \(error)")
            }
        }
    }

    /// Creates and configures a private queue context.
    private func newTaskContext() -> NSManagedObjectContext {
        let taskContext = container.newBackgroundContext()
        taskContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // If needed, ensure the background context
        // stays up to date with changes from
        // the parent
        taskContext.automaticallyMergesChangesFromParent = true

        // Add name and author to identify source of persistent history changes.
        taskContext.name = "importContext"
        taskContext.transactionAuthor = "backgroundTask"
        return taskContext
    }

}

