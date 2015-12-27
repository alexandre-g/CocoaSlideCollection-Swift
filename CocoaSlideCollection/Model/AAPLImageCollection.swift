//
//  AAPLImageCollection.swift
//  CocoaSlideCollection
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/12/24.
//
//
/*
    Copyright (C) 2015 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample‚Äôs licensing information

    Abstract:
    This is the "ImageCollection" class declaration.
*/

import Cocoa

let imageFilesKey = "imageFiles"

// An AAPLImageCollection encapsulates a list of AAPLImageFile objects, together with a rootURL that identifies the folder (if any) where we found them.  It also has a list of associated Tags, each of which can return the list of ImageFiles to which it's applied.
@objc(AAPLImageCollection)
class AAPLImageCollection: NSObject {
    
    //MARK: Properties
    
    private(set) var rootURL: NSURL?
    @objc private(set) dynamic var imageFiles: [AAPLImageFile] = []
    
    private var fileTreeWatcherThread: AAPLFileTreeWatcherThread?
    private var fileTreeScanQueue: NSOperationQueue
    
    private var imageFilesByURL: [NSURL: AAPLImageFile] = [:]
    private(set) var untaggedImageFiles: [AAPLImageFile] = []
    
    @objc dynamic private(set) var tags: [AAPLTag] = []
    private var tagsByName: [String: AAPLTag] = [:]
    
    
    init(rootURL newRootURL: NSURL) {
        
        rootURL = (newRootURL.copy() as! NSURL)
        let queue = NSOperationQueue()
        queue.name = "AAPLImageCollection File Tree Scan Queue"
        fileTreeScanQueue = queue
        
        /*
        Start watching the folder for changes.  Note that the "self" in this
        block creates a retain cycle.  To break it, we must
        -stopWatchingFolder when closing a browser window.
        */
        super.init()
        fileTreeWatcherThread = AAPLFileTreeWatcherThread(path: newRootURL.path!) {
            
            // When we detect a change in the folder, scan it to find out what changed.
            self.startOrRestartFileTreeScan()
        }
        fileTreeWatcherThread!.start()
    }
    
    
    //MARK: Querying the List of ImageFiles
    
    func imageFileForURL(imageFileURL: NSURL) -> AAPLImageFile? {
        return imageFilesByURL[imageFileURL]
    }
    
    
    //MARK: Modifying the List of ImageFiles
    
    func addImageFile(imageFile: AAPLImageFile) {
        self.insertImageFile(imageFile, atIndex: imageFiles.count)
    }
    
    func insertImageFile(imageFile: AAPLImageFile, atIndex index: Int) {
        
        // Add and update tags, based on the imageFile's tagNames.
        let tagNames = imageFile.tagNames
        if !tagNames.isEmpty {
            for tagName in imageFile.tagNames {
                var tag = self.tagWithName(tagName)
                if tag == nil {
                    tag = self.addTagWithName(tagName)
                }
                tag!.insertImageFile(imageFile)
            }
        } else {
            // ImageFile has no tags, so add it to "untaggedImageFiles" instead.
            let insertionIndex = untaggedImageFiles.indexOf(imageFile, inSortedRange: untaggedImageFiles.indices) {imageFile1, imageFile2 in
                return imageFile1.filenameWithoutExtension!.caseInsensitiveCompare(imageFile2.filenameWithoutExtension!)
            }
            untaggedImageFiles.insert(imageFile, atIndex: insertionIndex)
        }
        
        // Insert the imageFile into our "imageFiles" array (in a KVO-compliant way).
        self.mutableArrayValueForKey(imageFilesKey).insertObject(imageFile, atIndex: index)
        
        // Add the imageFile into our "imageFilesByURL" dictionary.
        imageFilesByURL[imageFile.url] = imageFile
    }
    
    func removeImageFile(imageFile: AAPLImageFile) {
        
        // Remove the imageFile from our "imageFiles" array (in a KVO-compliant way).
        self.mutableArrayValueForKey(imageFilesKey).removeObject(imageFile)
        
        // Remove the imageFile from our "imageFilesByURL" dictionary.
        imageFilesByURL.removeValueForKey(imageFile.url)
        
        // Remove the imageFile from the "imageFiles" arrays of its AAPLTags (if any).
        for tagName in imageFile.tagNames {
            if let tag = self.tagWithName(tagName) {
                tag.mutableArrayValueForKey("imageFiles").removeObject(imageFile)
            }
        }
    }
    
    func removeImageFileAtIndex(index: Int) {
        let imageFile = imageFiles[index]
        self.removeImageFile(imageFile)
    }
    
    func moveImageFileFromIndex(fromIndex: Int, toIndex: Int) {
        let imageFilesCount = imageFiles.count
        assert(fromIndex < imageFilesCount)
        assert(toIndex < imageFilesCount)  //###
        let imageFile = imageFiles[fromIndex]
        self.removeImageFileAtIndex(fromIndex)
        self.insertImageFile(imageFile, atIndex: (toIndex <= fromIndex) ? toIndex : (toIndex - 1))
    }
    
    
    //MARK: Modifying the List of Tags
    
    func tagWithName(name: String) -> AAPLTag? {
        return tagsByName[name]
    }
    
    func addTagWithName(name: String) -> AAPLTag {
        var tag = self.tagWithName(name)
        if tag == nil {
            tag = AAPLTag(name: name)
            tagsByName[name] = tag
            
            // Binary-search and insert, in alphabetized tags array.
            let insertionIndex = tags.indexOf(tag!, inSortedRange: tags.indices) {tag1, tag2 in
                return tag1.name.caseInsensitiveCompare(tag2.name)
            }
            tags.insert(tag!, atIndex: insertionIndex)
        }
        return tag!
    }
    
    
    //MARK: Finding Image Files
    
    func startOrRestartFileTreeScan() {
        synchronized(fileTreeScanQueue) {
            // Cancel any pending file tree scan operations.
            self.stopFileTreeScan()
            
            // Enqueue a new file tree scan operation.
            fileTreeScanQueue.addOperationWithBlock {
                
                /*
                Enumerate all of the image files in our given rootURL.  As we
                go, identify three groups of image files:
                
                (1) files that are in the catalog, but have since changed (the
                file's modification date is later than its last-cached date)
                
                (2) files that exist on disk but are not yet in the catalog
                (presumably the file was added and we should create an
                ImageFile instance for it)
                
                (3) files that exist in the ImageCollection but not in the
                folder (presumably the file was deleted and we should remove
                the corresponding ImageFile instance)
                */
                var filesToProcess = self.imageFiles
                var filesChanged: [AAPLImageFile] = []
                var urlsAdded: [NSURL] = []
                var filesRemoved: [AAPLImageFile] = []
                
                let directoryEnumerator = NSFileManager.defaultManager().enumeratorAtURL(self.rootURL!, includingPropertiesForKeys: [NSURLIsRegularFileKey, NSURLTypeIdentifierKey, NSURLContentModificationDateKey], options: [.SkipsSubdirectoryDescendants, .SkipsPackageDescendants]) {url, error in
                    NSLog("directoryEnumerator error: %@", error)
                    return true
                    }!
                for url in directoryEnumerator {
                    let url = url as! NSURL
                    block: do {
                        var isRegularFile: AnyObject? = nil
                        try url.getResourceValue(&isRegularFile, forKey: NSURLIsRegularFileKey)
                        guard (isRegularFile as! Bool) else {break block}
                        var fileType: AnyObject? = nil
                        try url.getResourceValue(&fileType, forKey: NSURLTypeIdentifierKey)
                        guard UTTypeConformsTo(fileType as! CFString, "public.image") else {break block}
                        
                        // Look for a corresponding entry in the catalog.
                        if let imageFile = self.imageFileForURL(url) {
                            // Check whether file has changed.
                            var modificationDate: AnyObject? = nil
                            do {
                                try url.getResourceValue(&modificationDate, forKey: NSURLContentModificationDateKey)
                                let modificationDate = modificationDate as! NSDate
                                if modificationDate.compare(imageFile.dateLastUpdated!) == .OrderedDescending {
                                    filesChanged.append(imageFile)
                                }
                            } catch _ {}
                            filesToProcess = filesToProcess.filter{$0 != imageFile}
                        } else {
                            // File was added.
                            urlsAdded.append(url)
                        }
                    } catch _ {}
                }
                
                // Check for images in the catalog for which no corresponding file was found.
                filesRemoved.appendContentsOf(filesToProcess)
                filesToProcess = []
                
                /*
                Perform our ImageCollection modifications on the main thread, so
                that corresponding KVO notifications and CollectionView updates will
                also happen on the main thread.
                */
                NSOperationQueue.mainQueue().addOperationWithBlock {
                    
                    // Remove ImageFiles for files we knew about that have disappeared.
                    for imageFile in filesRemoved {
                        self.removeImageFile(imageFile)
                    }
                    
                    // Add ImageFiles for files we've newly discovered.
                    for imageFileURL in urlsAdded {
                        let imageFile = AAPLImageFile(URL: imageFileURL)
                        self.addImageFile(imageFile)
                    }
                }
            }
        }
    }
    
    func stopFileTreeScan() {
        synchronized(fileTreeScanQueue) {
            fileTreeScanQueue.cancelAllOperations()
        }
    }
    
    func stopWatchingFolder() {
        fileTreeWatcherThread?.detachChangeHandler()
        fileTreeWatcherThread?.cancel()
        fileTreeWatcherThread = nil
    }
    
    
    //MARK: Teardown
    
    deinit {
        self.stopWatchingFolder()
    }
    
}
