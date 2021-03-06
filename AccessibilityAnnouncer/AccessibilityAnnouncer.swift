//
//  AccessibilityAnnouncer.swift
//  AccessibilityAnnouncer
//
//  Created by Sommer Panage on 9/11/15.
//  Copyright © 2015 Sommer Panage. All rights reserved.
//

import UIKit
import ReactiveCocoa

public final class AccessibilityAnnouncer {
    
    // Amount of time for which our announcer should retry a failing announcement before
    // giving up. We recommend no more than 3 seconds for this, otherwise the annoucnement
    // will be out of context. If 0 is set in the initializer, then there will be no retry
    // behavior by default.
    public let defaultRetryTimeout: NSTimeInterval
    
    private typealias AnnouncerProducer = SignalProducer<(), NoError>
    private typealias NotifierProducer = SignalProducer<(), NotificationError>
    
    private let signal: Signal<AnnouncerProducer, NoError>
    private let sink: Signal<AnnouncerProducer, NoError>.Observer
    private let disposable: Disposable
    
    public init(defaultTimeout: NSTimeInterval = 3.0) {
        self.defaultRetryTimeout = defaultTimeout
        
        (signal, sink) = Signal<AnnouncerProducer, NoError>.pipe()
        
        disposable = signal
            .flatten(.Concat)
            .observeNext {}!
    }
    
    deinit {
        disposable.dispose()
    }
    
    public func announce(announcement: String) {
        announce(announcement, withRetryTimeout: defaultRetryTimeout)
    }
    
    // Passing a timeout here overrides the default timeout for this announcement only.
    public func announce(announcement: String, withRetryTimeout timeout: NSTimeInterval) {
        let announcer = createProducerForAnnouncer(announcement)
        let notifier = createProducerForNotifier(announcement)
        
       let announceAndCheckNotificationProducer = announcer
            .promoteErrors(NotificationError)
            .concat(notifier)
        
        let retryTilTimeoutProducer = announceAndCheckNotificationProducer
            .retry(Int.max)
            .timeoutWithError(.AnnouncementTimedOut, afterInterval: timeout, onScheduler: QueueScheduler())
            .flatMapError { _ in AnnouncerProducer.empty }
        
        sink.sendNext(retryTilTimeoutProducer)
    }
    
    private func createProducerForAnnouncer(announcement: String) -> AnnouncerProducer {
        return SignalProducer { sink, disposable in
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, announcement)
            sink.sendCompleted()
        }
    }
    
    private func createProducerForNotifier(announcement: String) -> NotifierProducer {
        return NSNotificationCenter.defaultCenter().rac_notifications(UIAccessibilityAnnouncementDidFinishNotification, object: nil)
            .map { $0.userInfo! }
            .filter { $0[UIAccessibilityAnnouncementKeyStringValue]!.isEqual(announcement) }
            .take(1)
            .promoteErrors(NotificationError)
            .flatMap(.Merge) { userInfo -> NotifierProducer in
                let success = userInfo[UIAccessibilityAnnouncementKeyWasSuccessful]!.boolValue!
                
                if (success) {
                   return .empty
                } else {
                    return SignalProducer(error: .AnnouncementFailed)
                }
            }
    }
    
    private enum NotificationError: ErrorType {
        case AnnouncementFailed
        case AnnouncementTimedOut
    }
}