//
//  DetailViewController.swift
//  ekCoreData38a
//
//  Created by Eric Kennedy on 8/14/23.
//

import CoreData
import Foundation
import UIKit

class DetailViewController: UIViewController, UITextFieldDelegate {
    var detailItem: NSManagedObject?
    @IBOutlet var textField: UITextField!
    @IBOutlet var detailLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()
        textField.delegate = self

        if let commit = detailItem as? Commit {
            self.textField.text = String(commit.message.prefix(50))
            detailLabel.text = "By \(commit.author.name) on \(commit.date.description)"
        } else if let author = detailItem as? Author {
            self.textField.text = author.name
            detailLabel.text = author.email
        } else {
            print("unknown detail type")
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .plain, target: self, action: #selector(save))

    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        let currentCharacterCount = textField.text?.count ?? 0
        if range.length + range.location > currentCharacterCount {
            // Return false if the attempted replacement length > currentCharacterCount.
            // This occurs after a long string is pasted in but this method prevents the paste,
            // followed by a shake to undo.
            // The undo buffer has text that isn't in searchBar.text? so the range will be out of bounds
            return false
        }
        let newLength = currentCharacterCount + string.count - range.length
        return newLength <= 50
    }

    @objc func save() {
        if let entity = detailItem, let text = textField.text {
            if let commit = entity as? Commit {
                commit.message = text
            } else if let author = entity as? Author {
                author.name = text
            } else {
                print("Error: entity could not be downcast to Commit or Author")
            }
            do {
                try entity.managedObjectContext?.save()
            } catch {
                print("Error occcured saving \(error)")
            }
            navigationController?.popViewController(animated: true)
        }
    }
}
