//
//  ViewController.swift
//  simpleCoreData
//
//  Created by Eric Kennedy on 8/15/23.
//

import CoreData
import UIKit

protocol ManagedObjectWithTitleSubtitle: NSManagedObject {
    var title: String { get }
    var subtitle: String { get }
}

struct ItemViewModel {
    var title: String
    var subtitle: String
    // var entityID: NSManagedObjectID
    var entity: NSManagedObject
}

class ViewController: UITableViewController {
    var container: NSPersistentContainer!
    var commitPredicate: NSPredicate?
    var items = [ItemViewModel]()

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Filter", style: .plain, target: self, action: #selector(changeFilter))

        container = NSPersistentContainer(name: "simpleModel")
        container.loadPersistentStores { storeDescription, error in
            // mergePolicy allows in memory object to overwrite prior Store value
            self.container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

            if let error {
                print("Unresolved error \(error)")
            }
        }

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
            commitAuthor = author
        }

        // use the author, either saved or new
        commit.author = commitAuthor
        // have the caller call save on the taskContext to avoid multiple dispatches to reload the tableview
    }

    @objc func changeFilter() {
           let ac = UIAlertController(title: "Filter items...", message: nil, preferredStyle: .actionSheet)

           ac.addAction(UIAlertAction(title: "Show only fixes", style: .default) { [unowned self] _ in
               self.commitPredicate = NSPredicate(format: "message CONTAINS[c] 'fix'") // [c] is predicate-speak for "case-insensitive"
               self.loadSavedData()
           })

           ac.addAction(UIAlertAction(title: "Ignore Pull Requests", style: .default) { [unowned self] _ in
               self.commitPredicate = NSPredicate(format: "NOT message BEGINSWITH 'Merge pull request'")
               self.loadSavedData()
           })

           ac.addAction(UIAlertAction(title: "Show only recent", style: .default) { [unowned self] _ in
               let twelveHoursAgo = Date().addingTimeInterval(-43200)
               self.commitPredicate = NSPredicate(format: "date > %@", twelveHoursAgo as NSDate)
               self.loadSavedData()
           })

           ac.addAction(UIAlertAction(title: "Show all commits", style: .default) { [unowned self] _ in
               self.commitPredicate = nil
               self.loadSavedData()
           })

           ac.addAction(UIAlertAction(title: "Show only Ben Barham commits", style: .default) { [unowned self] _ in
               self.commitPredicate = NSPredicate(format: "author.name == 'Ben Barham'")
               self.loadSavedData()
           })

           ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
           present(ac, animated: true)
       }

       func loadSavedData() {
           print("loadSavedData")
           fetchData(entity: Commit.self)
       }

        func fetchData<T: ManagedObjectWithTitleSubtitle>(entity: T.Type) {
            let fetchRequest = T.fetchRequest()
            let sort = NSSortDescriptor(key: "date", ascending: false)
            fetchRequest.sortDescriptors = [sort]
            do {
                fetchRequest.predicate = commitPredicate
                let rows = try container.viewContext.fetch(fetchRequest)

                print("Got \(rows.count) from CoreData")

                items.removeAll(keepingCapacity: true)
                for row in rows {
                    if let entity = row as? T {
                        let item = ItemViewModel(title: entity.title,
                                                 subtitle: entity.subtitle,
                                                 entity: entity)
                        items.append(item)
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

           let cell = tableView.dequeueReusableCell(withIdentifier: "Commit", for: indexPath)
           var config = cell.defaultContentConfiguration()

           if index < items.count {
               let item = items[index]
               config.text = item.title
               config.secondaryText = item.subtitle
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
               container.viewContext.delete(item.entity)
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

