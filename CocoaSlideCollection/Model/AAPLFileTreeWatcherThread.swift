//
//  AAPLFileTreeWatcherThread.swift
//  CocoaSlideCollection
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/12/24.
//
//
/*
    Copyright (C) 2015 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information

    Abstract:
    This is the "FileTreeWatcherThread" class declaration.
*/

import Cocoa
import CoreServices

@objc(AAPLFileTreeWatcherThread)
class AAPLFileTreeWatcherThread: NSThread {
    private var paths: [String]                 // array of paths we're watching (as NSStrings)
    private var handler: (()->Void)!          // the block to invoke when we sense a change
    private var fsEventStream: FSEventStreamRef = nil // the FSEventStream that's informing us of changes
    
    
    /*
    Creates a new AAPLFileTreeWatcherThread that monitors the file subtree
    specified by the given path, and invokes the given "changeHandler" block
    each time a change in the file subtree is detected.
    
    Send -start to the returned instance to start watching the file system.
    Send -cancel to stop.
    (AAPLFileTreeWatcherThread inherits these API methods from NSThread.)
    */
    init(path pathToWatch: String, changeHandler: ()->Void) {
        paths = [pathToWatch]
        super.init()
        self.name = "AAPLFileTreeWatcherThread"
        synchronized(self) {
            handler = changeHandler
        }
    }
    
    /*
    Invoked by AAPLFileTreeWatcherThread to schedule main-thread invocation of
    its changeHandler.
    */
    func invokeChangeHandler() {
        synchronized(self) {
            if let handler = handler {
                NSOperationQueue.mainQueue().addOperationWithBlock(handler)
            }
        }
    }
    
    /*
    Invoke this to zero out the thread's "changeHandler" pointer when things it
    operates on are about to go away.  (Sending -cancel to the thread isn't
    sufficient to ensure that it won't invoke its "changeHandler" one more
    time.)
    */
    func detachChangeHandler() {
        synchronized(self) {
            handler = nil
        }
    }
    
    override func main() {
        autoreleasepool {
            
            // Create our fsEventStream.
            var context: FSEventStreamContext = FSEventStreamContext()
            context.version = 0
            context.info = UnsafeMutablePointer(unsafeAddressOf(self))
            context.retain = nil
            context.release = nil
            context.copyDescription = nil
            fsEventStream = FSEventStreamCreate(kCFAllocatorDefault, AAPLFileTreeWatcherEventStreamCallback, &context, paths, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0, FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagIgnoreSelf))
            if fsEventStream != nil {
                
                // Schedule the fsEventStream on our thread's run loop.
                let runLoop = NSRunLoop.currentRunLoop()
                let cfRunLoop = runLoop.getCFRunLoop()
                FSEventStreamScheduleWithRunLoop(fsEventStream, cfRunLoop, kCFRunLoopCommonModes)
                
                // Open the faucet.
                FSEventStreamStart(fsEventStream)
                
                // Run until we're asked to stop.
                while !self.cancelled {
                    runLoop.runUntilDate(NSDate(timeIntervalSinceNow: 0.25))
                }
                
                // Shut off the faucet.
                FSEventStreamStop(fsEventStream)
                
                // Unschedule the fsEventStream on our thread's run loop.
                FSEventStreamUnscheduleFromRunLoop(fsEventStream, cfRunLoop, kCFRunLoopCommonModes)
                
                // Invalidate and release fsEventStream.
                FSEventStreamInvalidate(fsEventStream)
                FSEventStreamRelease(fsEventStream)
                fsEventStream = nil
            }
        }
    }
    
}

private func AAPLFileTreeWatcherEventStreamCallback(streamRef: ConstFSEventStreamRef, clientCallBackInfo: UnsafeMutablePointer<Void>, numEvents: size_t, eventPaths: UnsafeMutablePointer<Void>, eventFlags: UnsafePointer<FSEventStreamEventFlags>, eventIds: UnsafePointer<FSEventStreamEventId>)
{
    if numEvents > 0 {
        let thread = unsafeBitCast(clientCallBackInfo, AAPLFileTreeWatcherThread.self)
        
        thread.invokeChangeHandler()
    }
}
