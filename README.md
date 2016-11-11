# [DEPRECATED] Cake

⚠️ **This repository is no longer maintained or supported. New pull requests will not be reviewed.** ⚠️

Cake is a wrapper for Cocoapods that aims to replicate the behavior of Carthage while maintaining the central
database of Pods that Cocoapods provides. This allows you to pull pods and manage dependencies using Cocoapods without
the frustrations inherent in setting up your Podfile properly.

## Requirements

Cake requires OSX 10.11 or greater. 

## Installation

Simply download the zip from the Releases section of this repo and copy it to the folder you would like to reference it from. 

## Usage

Cake downloads all the dependencies listed in your Podfile and builds them into compiled frameworks. Cake disregards the
project integration of Cocoapods in lieu of a more manual integration into your project.

### Setting up your Podfile

Cake uses Cocoapods in order to resolve dependencies, so using Cake is very similar to using Cocoapods. Simply create a `Podfile` and 
list the pods you wish to use. However, because Cake uses the `--no-integrate` option, you are not able to specify targets, projects, 
or other configuration data. As a result, it is best to place all of your pods in the Podfile at the root instead of using nesting:

```ruby
platform :ios, '9.0'
use_frameworks!

pod 'Alamofire', '3.3.0'
pod 'Argo', '2.3.0'
pod 'Curry', '2.0.0'
pod 'ReactiveCocoa', '4.1.0'
```

### `build`

Run the `build` command to have cake update your dependencies and compile the new frameworks. By default, this will diff each dependency
against the version found on disk and only update the Pods that have been updated or changed. This is to make each subsequend `build` 
faster as it need not build all dependencies each time.

All frameworks will be output to `./Cake/build/iOS`. Any pre-compiled frameworks or libraries from Cocoapods 
will automatically be copied over to the build folder along with any resources.

#### Options

* `--verbose`: Outputs all information to standard output, including `xcodebuild` and `pod install`. Recommended for debugging issues
* `--clean`: Forces a refresh of all dependencies; will delete the existing `./Cake` folder before running the build command
* `--sdk`: Valid options are `simulator` or `iphone`. By default, Cake generates a fat framework for all architectures. Use this if you only wish to build for one. Reduces build time, but should only be used if needed.

### `check-dependencies`

A replacement for the default Cocoapods `Manifest.lock` build phase. It is recommended that you use this as one of your first build phases
in order to verify that the dependencies installed are the ones that are set in your `Podfile.lock`.

#### Options

* `--strict`: Throws a compile error if any differences are found. By default, this only emits warnings that dependencies are out of sync.

### `strip-frameworks`

Reduces the fat frameworks down to only include the architectures valid for the output app. This is required to get around an App Store
submission build. This should be one of your final build phases.

