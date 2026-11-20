//
//  RefreshAppOperation.swift
//  AltStore
//
//  Created by Riley Testut on 2/27/20.
//  Copyright © 2020 Riley Testut. All rights reserved.
//

import Foundation
import CoreData
import SideSign

final class RefreshAppOperation: BasePipelineOperation<InstallAppOperationContext, InstalledApp>, @unchecked Sendable {
    
    override func execute(parentProgress: Progress?) async throws -> InstalledApp {
        let startTime = CFAbsoluteTimeGetCurrent()
        debugLog("[RefreshAppOperation] execute() started")
        defer {
            let elapsed = CFAbsoluteTimeGetCurrent() - startTime
            debugLog("[RefreshAppOperation] execute() took: \(String(format: "%.3fs", elapsed))")
        }
        try await super.executePreconditionCheck(parentProgress: parentProgress)
        
        guard let profiles = self.context.provisioningProfiles else {
            throw OperationError.invalidParameters("RefreshAppOperation.execute: self.context.provisioningProfiles is nil")
        }
        
        guard let appBundle = self.context.targetAppBundle else {
            throw OperationError.invalidParameters("RefreshAppOperation: context.targetAppBundle is nil")
        }
        self.setProgress(10)
        
        if self.context.isCellularRefreshGroup {
            debugLog("[RefreshAppOperation] Queueing \(self.context.bundleIdentifier) into batch profile injection (isCellularRefreshGroup = true)")
            self.context.sharedContext.addPendingProfileBatch(PendingProfileBatch(
                bundleID: self.context.bundleIdentifier,
                profiles: profiles.values.map { $0.data },
                app: self.context.installedApp,
                certStatus: self.context.targetCertStatus
            ))
            self.setProgress(85)
            guard let app = self.context.installedApp else {
                throw OperationError.invalidParameters("RefreshAppOperation: context.installedApp is nil")
            }
            return app
        }
        
        do {
            await CellularRefreshManager.shared.turnOffDataIfNeeded()
            for p in profiles {
                try await installProvisioningProfiles(p.value.data)
            }
            await CellularRefreshManager.shared.turnOnDataIfNeeded()
        } catch {
            await CellularRefreshManager.shared.turnOnDataIfNeeded()
            throw error
        }
        
        self.setProgress(80)
        let dbContext = self.context.dbBackgroundContext
        
        let installedApp = try await dbContext.perform {
            try self.updateInstalledApp(for: appBundle, profiles: profiles, in: dbContext)
        }
        
        self.setProgress(100)
        return installedApp
    }
    
    private func updateInstalledApp(for appBundle: ALTApplication, profiles: [String: ALTProvisioningProfile], in dbContext: NSManagedObjectContext) throws -> InstalledApp {
        self.setProgress(self.progress.completedUnitCount + 1)
        
        guard let mainApp = self.context.installedApp,
              let installedApp = dbContext.object(with: mainApp.objectID) as? InstalledApp else {
            throw OperationError.invalidParameters("Could not find installed database record for '\(appBundle.name)'")
        }

        // Use the main app's own provisioning profile, keyed by its (re)signed bundle identifier,
        // rather than profiles.values.first! — for apps with extensions that dict's first value can be
        // an extension's profile (which may carry a different expiration date) and would corrupt the
        // main app's recorded expiry.
        let mainProfile = profiles[installedApp.resignedBundleIdentifier]
            ?? profiles[self.context.targetBundleIdentifier]
            ?? profiles.values.first
        guard let mainProfile else {
            throw OperationError.invalidParameters("RefreshAppOperation: could not locate main provisioning profile for '\(installedApp.resignedBundleIdentifier)'")
        }
        installedApp.update(provisioningProfile: mainProfile)
        
        if let certStatus = self.context.targetCertStatus {
            installedApp.certificateStatus = certStatus
        }

        for installedExtension in installedApp.appExtensions {
            // Extension profiles are keyed by the *re-signed* (effective) bundle identifier, not the
            // original one, so look that up first. Fall back to the original ID, then to the main app's
            // profile (e.g. when a single profile is shared across all extensions via useMainProfile).
            // Previously this lookup used the original ID and `continue`d on miss, leaving every
            // extension's refreshedDate/expirationDate stale after a refresh.
            let extensionProfile = profiles[installedExtension.resignedBundleIdentifier]
                ?? profiles[installedExtension.bundleIdentifier]
                ?? mainProfile
            installedExtension.update(provisioningProfile: extensionProfile)
        }
        return installedApp
    }
}
