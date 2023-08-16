//
//  DetailViewController.swift
//  ekCoreData38a
//
//  Created by Eric Kennedy on 8/14/23.
//

import Foundation
import UIKit

class DetailViewController: UIViewController, UITextFieldDelegate {
    var detailItem: ItemViewModel?
    @IBOutlet var textField: UITextField!
    @IBOutlet var detailLabel: UILabel!

    override func viewDidLoad() {
        super.viewDidLoad()

        if let detail = self.detailItem {
            textField.text = String(detail.title.prefix(50))
            textField.delegate = self
            detailLabel.text = detail.subtitle
            //"\(detail.author.name) \n \(detail.sha) \(detail.date)"

            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Save", style: .plain, target: self, action: #selector(save))
        }
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
        if var detail = detailItem, let text = textField.text {
            print("before save", detail.title, text)
            if let entity = detail.entity as? Commit {
                entity.message = text
                detail.title = text
            } else {
                print("other kind of entity")
            }
            do {
                try detail.entity.managedObjectContext?.save()
            } catch {
                print("Error occcured saving \(error)")
            }
            navigationController?.popViewController(animated: true)
        }
    }
}
