//
//  Exports.swift
//  Role: TEMCore re-exports the two targets below it, so TEMSession, the app and the tests keep one `import TEMCore`: TEMBase (the app
//        name, the calibrated image and its pixels, unit display, text lines, checked conversions, a scan row's parallel work, the
//        words for an error) and TEMSEM (the SEM program's ports, #849). Inside TEMCore each file imports them itself.
//

@_exported import TEMBase
@_exported import TEMSEM
// The orientation maths TEMSEM's own `Orientation/` held until #850 (DiffractoKit 0.25.0): re-exported as TEMSEM's were, so a file that
// reads a rotation's or a colour key's members through TEMCore keeps compiling.
@_exported import DiffractoGeometry
@_exported import DiffractoOrientation
