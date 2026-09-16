//
//  AppDelegate.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 12/2/25.
//

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {

    static var orientationLock = UIInterfaceOrientationMask.portrait

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask
    {
        return AppDelegate.orientationLock
    }
}
