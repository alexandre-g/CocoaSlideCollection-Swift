//
//  AAPLAppDelegate.swift
//  CocoaSlideCollection
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/12/27.
//
//
/*
    Copyright (C) 2015 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample‚Äôs licensing information

    Abstract:
    This is the application delegate declaration.
*/

import Cocoa

/*
The application delegate opens a browser window for
"/Library/Desktop Pictures" on launch, and handles requests to open
additional browser windows.
*/

@NSApplicationMain
@objc(AAPLAppDelegate)
class AAPLAppDelegate: NSObject, NSApplicationDelegate {
    private var browserWindowControllers: Set<AAPLBrowserWindowController> = []

    /*
    Given a file:// URL that points to a folder, opens a new browser window that
    displays the image files in that folder.
    */
    private func openBrowserWindowForFolderURL(_ folderURL: URL) {
        let browserWindowController = AAPLBrowserWindowController(rootURL: folderURL)
        browserWindowController.showWindow(self)

        /*
        Add browserWindowController to browserWindowControllers, to keep it
        alive.
        */
        browserWindowControllers.insert(browserWindowController)

        /*
        Watch for the window to be closed, so we can let it and its
        controller go.
        */
        if let browserWindow = browserWindowController.window {
            NotificationCenter.default.addObserver(self, selector: #selector(AAPLAppDelegate.browserWindowWillClose(_:)), name: NSNotification.Name.NSWindowWillClose, object: browserWindow)
        }
    }

    // CocoaSlideCollection's "File" -> "Browse Folder..." (Cmd+O) menu item sends this.
    /*
    Action method invoked by the "File" -> "Open Browser..." menu command.
    Prompts the user to choose a folder, using a standard Open panel, then opens
    a browser window for that folder using the method above.
    */
    @IBAction func openBrowserWindow(_: AnyObject?) {

        let openPanel = NSOpenPanel()
        openPanel.prompt = "Choose"
        openPanel.message = "Choose a directory containing images:"
        openPanel.title = "Choose Directory"
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        let pictureDirectories = NSSearchPathForDirectoriesInDomains(.picturesDirectory, .userDomainMask, true)
        openPanel.directoryURL = URL(fileURLWithPath: pictureDirectories[0])

        openPanel.begin { result in
            if result == NSModalResponseOK {
                self.openBrowserWindowForFolderURL(openPanel.urls[0])
            }
        }
    }

    // CocoaSlideCollection's "File" -> "Save Order..." (Cmd+S) menu item sends this.
    /*
    Action method invoked by the "File" -> "Save Order..." menu command.
    Save the new order to disk by renaming files on disk appropriately
    */
    @IBAction func saveOrder(_: AnyObject) {
        let imageFiles = browserWindowControllers.first!.imageCollection!.imageFiles
        /*imageFiles.forEach { image in
            if !image.bracketedSiblings.isEmpty {
                print("\(image.filename): [0]")
                image.bracketedSiblings.enumerated().forEach { i, photo in
                    print("\(photo) [\(i+1)] ")
                }
            } else {
                print("\(image.filename): no bracket")
            }
        }
        return*/

        var counter = 0

        func getNextCounterValue() -> String {
            counter += 1
            var counterValue = "\(counter)"
            while counterValue.count < 3 {
                counterValue = "0" + counterValue
            }
            return counterValue
        }

        validate()

        imageFiles.forEach { image in

            if !image.bracketedSiblings.isEmpty {

                let imageNumber = getNextCounterValue()
                /// First image in bracket series (0 exposure bias)
                let newPath = image.url.path.replacingOccurrences(of: image.filenameWithoutExtension!, with: "\(imageNumber)a")
                renameFile(atPath: image.url.path, toPath: newPath)

                /// Second and third images in bracket series (-3, +3 bias)
                image.bracketedSiblings.enumerated().forEach { i, bracket in
                    let bracketedImagePath = image.url.path.replacingOccurrences(of: image.filename, with: bracket)
                    let newPath = bracketedImagePath.replacingOccurrences(of: bracket, with: imageNumber + (i == 0 ? "b" : "c") + "." + image.url.pathExtension)
                    renameFile(atPath: bracketedImagePath, toPath: newPath)
                }

            } else {
                let newPath = image.url.path.replacingOccurrences(of: image.filenameWithoutExtension!, with: "\(getNextCounterValue())")
                renameFile(atPath: image.url.path, toPath: newPath)
            }
        }

        let alert = NSAlert.init()
        alert.messageText = "Переименовано"
        alert.informativeText = "Всего: \(imageFiles.count) (если считать брекеты то больше)"
        alert.addButton(withTitle: "Окей")

        let result = alert.runModal()

        switch result {
        case NSModalResponseOK:
            NSApp.terminate(nil)
        default:
            print("There is no provision for further buttons")
        }
    }

    @discardableResult
    func validate() -> Bool {
        let imageFiles = browserWindowControllers.first!.imageCollection!.imageFiles
        var invalid = false
        var message = ""

        imageFiles.forEach {
            if $0.bracketedSiblings.count > 2 {
                invalid = true
                message += "Проверь эти фотки - тут либо что то лишнее либо рядом с ними не хватает фоток для другого брекета: "
                message += "\($0.filename), "
                message += $0.bracketedSiblings.joined(separator: ", ")

            }
        }

        if invalid {
            let alert = NSAlert.init()
            alert.messageText = "Проблемка.."
            alert.informativeText = message
            alert.addButton(withTitle: "Закрыть")
            alert.runModal()
            NSApp.terminate(nil)
        }
        return invalid
    }

    func renameFile(atPath: String, toPath: String) {
        print("\(atPath) -> \(toPath)")
        try! FileManager.default.moveItem(atPath: atPath, toPath: toPath)
    }

    // When a browser window is closed, release its BrowserWindowController.
    func browserWindowWillClose(_ notification: Notification) {
        let browserWindow = notification.object as! NSWindow
        browserWindowControllers.remove(browserWindow.delegate as! AAPLBrowserWindowController)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.NSWindowWillClose, object: browserWindow)
    }

    //MARK: NSApplicationDelegate Methods

    // Browse a default folder on launch.
    func applicationDidFinishLaunching(_ notification: Notification) {
        openBrowserWindow(nil)
        //self.openBrowserWindowForFolderURL(URL(fileURLWithPath: "/Library/Desktop Pictures"))
        //self.openBrowserWindowForFolderURL(URL(fileURLWithPath: "/Users/alex/Desktop/Shared/Room"))
        //self.openBrowserWindowForFolderURL(URL(fileURLWithPath: "/Volumes/SM951/2018.11.17 Aquarius"))
    }
}
