//
//  Commit+CoreDataProperties.swift
//  simpleCoreData
//
//  Created by Eric Kennedy on 8/15/23.
//
//

import Foundation
import CoreData


extension Commit {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<Commit> {
        return NSFetchRequest<Commit>(entityName: "Commit")
    }

    @NSManaged public var date: Date
    @NSManaged public var sha: String
    @NSManaged public var url: String
    @NSManaged public var message: String
    @NSManaged public var author: Author

}

extension Commit : Identifiable {

}
