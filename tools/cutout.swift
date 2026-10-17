// Usage: swift tools/cutout.swift <input image> <output.png>
// Lifts the main subject out of a photo with Apple's Vision (macOS 14+) and crops it tight.
import AppKit
import Vision
import CoreImage

let args = CommandLine.arguments
let input = URL(fileURLWithPath: args[1]), output = URL(fileURLWithPath: args[2])
guard let ci = CIImage(contentsOf: input) else { fatalError("can't read \(input.path)") }
let req = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(ciImage: ci)
try handler.perform([req])
guard let obs = req.results?.first else { fatalError("no subject found") }
let buf = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: true)
let out = CIImage(cvPixelBuffer: buf)
let ctx = CIContext()
guard let cg = ctx.createCGImage(out, from: out.extent) else { fatalError("render failed") }
let rep = NSBitmapImageRep(cgImage: cg)
try rep.representation(using: .png, properties: [:])!.write(to: output)
print("wrote \(output.path) \(cg.width)x\(cg.height), instances: \(obs.allInstances.count)")
