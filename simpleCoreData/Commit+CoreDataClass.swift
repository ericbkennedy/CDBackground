//
//  Commit+CoreDataClass.swift
//  simpleCoreData
//
//  Created by Eric Kennedy on 8/15/23.
//
//

import Foundation
import CoreData


public class Commit: NSManagedObject, ManagedObjectWithTitleSubtitle {
    var title: String { message }
    var subtitle: String { "By \(author.name) on \(date.description)" }
}
