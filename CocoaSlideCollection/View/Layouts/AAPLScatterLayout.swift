//
//  AAPLScatterLayout.swift
//  CocoaSlideCollection
//
//  Translated by OOPer in cooperation with shlab.jp, on 2015/12/26.
//
//
/*
    Copyright (C) 2015 Apple Inc. All Rights Reserved.
    See LICENSE.txt for this sample’s licensing information

    Abstract:
    This is the "ScatterLayout" class declaration.
*/

import Cocoa

// Positions items randomly, within the available area.
@objc(AAPLScatterLayout)
class AAPLScatterLayout: AAPLSlideLayout {
    private var cachedItemFrames: [NSIndexPath: NSRect] = [:]
    
    override func layoutAttributesForItemAtIndexPath(indexPath: NSIndexPath) -> NSCollectionViewLayoutAttributes? {
        var frameValue = cachedItemFrames[indexPath]
        if frameValue == nil {
            var p: NSPoint = NSPoint()
            p.x = box.origin.x + CGFloat(drand48()) * (box.size.width - itemSize.width)
            p.y = box.origin.y + CGFloat(drand48()) * (box.size.height - itemSize.height)
            frameValue = NSMakeRect(p.x, p.y, itemSize.width, itemSize.height)
            cachedItemFrames[indexPath] = frameValue!
        }
        
        let attributes = (self.dynamicType.layoutAttributesClass() as! NSCollectionViewLayoutAttributes.Type).init(forItemWithIndexPath: indexPath)
        attributes.frame = frameValue!
        attributes.zIndex = indexPath.item
        return attributes
    }
    
}