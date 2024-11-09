//
//  InjectionHybrid.swift
//  InjectionNext
//
//  Created by John Holdsworth on 09/11/2024.
//  Copyright © 2024 John Holdsworth. All rights reserved.
//

class InjectionHybrid: InjectionBase {
    var recompiler = HybridCompiler()

    override func inject(source: String) {
        if MonitorXcode.runningXcode == nil {
            MonitorXcode.compileQueue.async {
                self.recompiler.inject(source: source)
            }
        }
    }
}

class HybridCompiler: NextCompiler {
    
    var recompiler = Recompiler()

    override func recompile(source: String, platform: String) ->  String? {
        return recompiler.recompile(source: source, dylink: false)
    }
}
