//
//  ForceLandscapeOnly.swift
//  MyPianoInstructor
//
//  Created by Jason Fang on 12/2/25.
//
import SwiftUI

struct ForceLandscape: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear {
                setLandscape()
            }
            .onDisappear {
                setPortrait()
            }
    }
}

extension View {
    func landscapeOnly() -> some View {
        self.modifier(ForceLandscape())
    }
}

private func setLandscape() {
    AppDelegate.orientationLock = .landscape
    
    DispatchQueue.main.async {
        // 1. Force the physical rotation (still required for strict enforcement)
        if #available(iOS 16.0, *) {
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape))
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        }
        
        // 2. Tell the system to refresh orientation state (The fix for your warning)
        if #available(iOS 16.0, *) {
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            windowScene?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}

private func setPortrait() {
    AppDelegate.orientationLock = .portrait
    
    DispatchQueue.main.async {
        // 1. Force the physical rotation
        if #available(iOS 16.0, *) {
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            windowScene?.requestGeometryUpdate(.iOS(interfaceOrientations: .portrait))
        } else {
            UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        }
        
        // 2. Tell the system to refresh orientation state
        if #available(iOS 16.0, *) {
            let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene
            windowScene?.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        } else {
            UIViewController.attemptRotationToDeviceOrientation()
        }
    }
}
