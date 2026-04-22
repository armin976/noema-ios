---
title: Core ML
source: https://developer.apple.com/documentation/coreml
timestamp: 2026-03-08T17:49:16.406Z
---

## Core ML models

- [Getting a Core ML Model](/documentation/coreml/getting-a-core-ml-model)
- [Updating a Model File to a Model Package](/documentation/coreml/updating-a-model-file-to-a-model-package)
- [Integrating a Core ML Model into Your App](/documentation/coreml/integrating-a-core-ml-model-into-your-app)
- [MLModel](/documentation/coreml/mlmodel)

### Loading a model

- [class func load(contentsOf: URL, configuration: MLModelConfiguration) async throws -> MLModel](/documentation/coreml/mlmodel/load(contentsof:configuration:))
- [class func load(MLModelAsset, configuration: MLModelConfiguration, completionHandler: (MLModel?, (any Error)?) -> Void)](/documentation/coreml/mlmodel/load(_:configuration:completionhandler:))
- [class func load(contentsOf: URL, configuration: MLModelConfiguration, completionHandler: (Result<MLModel, any Error>) -> Void)](/documentation/coreml/mlmodel/load(contentsof:configuration:completionhandler:))
- [convenience init(contentsOf: URL) throws](/documentation/coreml/mlmodel/init(contentsof:))
- [convenience init(contentsOf: URL, configuration: MLModelConfiguration) throws](/documentation/coreml/mlmodel/init(contentsof:configuration:))
- [convenience init(contentsOfURL: URL) throws](/documentation/coreml/mlmodel/init(contentsofurl:))
- [convenience init(contentsOfURL: URL, configuration: MLModelConfiguration) throws](/documentation/coreml/mlmodel/init(contentsofurl:configuration:))

### Compiling a model

- [class compileModel(at:)](/documentation/coreml/mlmodel/compilemodel(at:))
- [class func compileModel(at: URL, completionHandler: (Result<URL, any Error>) -> Void)](/documentation/coreml/mlmodel/compilemodel(at:completionhandler:))

### Making predictions

- [func prediction(from:)](/documentation/coreml/mlmodel/prediction(from:))
- [func prediction(from:options:)](/documentation/coreml/mlmodel/prediction(from:options:))
- [func predictions(fromBatch: any MLBatchProvider) throws -> any MLBatchProvider](/documentation/coreml/mlmodel/predictions(frombatch:))
- [func predictions(from: any MLBatchProvider, options: MLPredictionOptions) throws -> any MLBatchProvider](/documentation/coreml/mlmodel/predictions(from:options:))
- [func prediction(from:using:)](/documentation/coreml/mlmodel/prediction(from:using:))
- [func prediction(from:using:options:)](/documentation/coreml/mlmodel/prediction(from:using:options:))
- [MLPredictionOptions](/documentation/coreml/mlpredictionoptions)

#### Getting features

- [var outputBackings: [String : Any]](/documentation/coreml/mlpredictionoptions/outputbackings)

#### Restricting computation to the CPU

- [var usesCPUOnly: Bool](/documentation/coreml/mlpredictionoptions/usescpuonly)

### Making state

- [func makeState() -> MLState](/documentation/coreml/mlmodel/makestate())

### Inspecting a model

- [static var availableComputeDevices: [MLComputeDevice]](/documentation/coreml/mlmodel/availablecomputedevices-6klyt)
- [var configuration: MLModelConfiguration](/documentation/coreml/mlmodel/configuration)
- [var modelDescription: MLModelDescription](/documentation/coreml/mlmodel/modeldescription)
- [MLModelDescription](/documentation/coreml/mlmodeldescription)

#### Accessing feature descriptions

- [var stateDescriptionsByName: [String : MLFeatureDescription]](/documentation/coreml/mlmodeldescription/statedescriptionsbyname)
- [var inputDescriptionsByName: [String : MLFeatureDescription]](/documentation/coreml/mlmodeldescription/inputdescriptionsbyname)
- [var outputDescriptionsByName: [String : MLFeatureDescription]](/documentation/coreml/mlmodeldescription/outputdescriptionsbyname)
- [MLFeatureDescription](/documentation/coreml/mlfeaturedescription)

##### Inspecting a feature

- [var name: String](/documentation/coreml/mlfeaturedescription/name)
- [var type: MLFeatureType](/documentation/coreml/mlfeaturedescription/type)
- [MLFeatureType](/documentation/coreml/mlfeaturetype)

###### Feature types

- [case int64](/documentation/coreml/mlfeaturetype/int64)
- [case double](/documentation/coreml/mlfeaturetype/double)
- [case image](/documentation/coreml/mlfeaturetype/image)
- [case multiArray](/documentation/coreml/mlfeaturetype/multiarray)
- [case string](/documentation/coreml/mlfeaturetype/string)
- [case dictionary](/documentation/coreml/mlfeaturetype/dictionary)
- [case sequence](/documentation/coreml/mlfeaturetype/sequence)
- [case state](/documentation/coreml/mlfeaturetype/state)
- [case invalid](/documentation/coreml/mlfeaturetype/invalid)

###### Creating a feature type

- [init?(rawValue: Int)](/documentation/coreml/mlfeaturetype/init(rawvalue:))
- [var isOptional: Bool](/documentation/coreml/mlfeaturedescription/isoptional)

##### Checking for validity

- [func isAllowedValue(MLFeatureValue) -> Bool](/documentation/coreml/mlfeaturedescription/isallowedvalue(_:))

##### Accessing feature constraints

- [var stateConstraint: MLStateConstraint?](/documentation/coreml/mlfeaturedescription/stateconstraint)
- [var imageConstraint: MLImageConstraint?](/documentation/coreml/mlfeaturedescription/imageconstraint)
- [MLImageConstraint](/documentation/coreml/mlimageconstraint)

###### Accessing the constraints

- [var pixelsWide: Int](/documentation/coreml/mlimageconstraint/pixelswide)
- [var pixelsHigh: Int](/documentation/coreml/mlimageconstraint/pixelshigh)
- [var pixelFormatType: OSType](/documentation/coreml/mlimageconstraint/pixelformattype)

###### Inspecting acceptable sizes

- [var sizeConstraint: MLImageSizeConstraint](/documentation/coreml/mlimageconstraint/sizeconstraint)
- [MLImageSizeConstraint](/documentation/coreml/mlimagesizeconstraint)

###### Determining relevant constraints

- [var type: MLImageSizeConstraintType](/documentation/coreml/mlimagesizeconstraint/type)
- [MLImageSizeConstraintType](/documentation/coreml/mlimagesizeconstrainttype)

###### Constraint types

- [case range](/documentation/coreml/mlimagesizeconstrainttype/range)
- [case enumerated](/documentation/coreml/mlimagesizeconstrainttype/enumerated)
- [case unspecified](/documentation/coreml/mlimagesizeconstrainttype/unspecified)

###### Creating a constraint type

- [init?(rawValue: Int)](/documentation/coreml/mlimagesizeconstrainttype/init(rawvalue:))

###### Accessing the image size ranges

- [var pixelsWideRange: NSRange](/documentation/coreml/mlimagesizeconstraint/pixelswiderange)
- [var pixelsHighRange: NSRange](/documentation/coreml/mlimagesizeconstraint/pixelshighrange)

###### Accessing the enumerated image sizes

- [var enumeratedImageSizes: [MLImageSize]](/documentation/coreml/mlimagesizeconstraint/enumeratedimagesizes)
- [MLImageSize](/documentation/coreml/mlimagesize)

###### Accessing an image size

- [var pixelsHigh: Int](/documentation/coreml/mlimagesize/pixelshigh)
- [var pixelsWide: Int](/documentation/coreml/mlimagesize/pixelswide)
- [var dictionaryConstraint: MLDictionaryConstraint?](/documentation/coreml/mlfeaturedescription/dictionaryconstraint)
- [MLDictionaryConstraint](/documentation/coreml/mldictionaryconstraint)

###### Accessing the constraint

- [var keyType: MLFeatureType](/documentation/coreml/mldictionaryconstraint/keytype)
- [var multiArrayConstraint: MLMultiArrayConstraint?](/documentation/coreml/mlfeaturedescription/multiarrayconstraint)
- [MLMultiArrayConstraint](/documentation/coreml/mlmultiarrayconstraint)

###### Accessing the Constraints

- [var shape: [NSNumber]](/documentation/coreml/mlmultiarrayconstraint/shape)
- [var dataType: MLMultiArrayDataType](/documentation/coreml/mlmultiarrayconstraint/datatype)
- [var shapeConstraint: MLMultiArrayShapeConstraint](/documentation/coreml/mlmultiarrayconstraint/shapeconstraint)
- [MLMultiArrayShapeConstraint](/documentation/coreml/mlmultiarrayshapeconstraint)

###### Accessing the Constraints

- [var enumeratedShapes: [[NSNumber]]](/documentation/coreml/mlmultiarrayshapeconstraint/enumeratedshapes)
- [var sizeRangeForDimension: [NSValue]](/documentation/coreml/mlmultiarrayshapeconstraint/sizerangefordimension)
- [var type: MLMultiArrayShapeConstraintType](/documentation/coreml/mlmultiarrayshapeconstraint/type)
- [MLMultiArrayShapeConstraintType](/documentation/coreml/mlmultiarrayshapeconstrainttype)

###### Constraint types

- [case enumerated](/documentation/coreml/mlmultiarrayshapeconstrainttype/enumerated)
- [case range](/documentation/coreml/mlmultiarrayshapeconstrainttype/range)
- [case unspecified](/documentation/coreml/mlmultiarrayshapeconstrainttype/unspecified)

###### Creating a constraint type

- [init?(rawValue: Int)](/documentation/coreml/mlmultiarrayshapeconstrainttype/init(rawvalue:))
- [var sequenceConstraint: MLSequenceConstraint?](/documentation/coreml/mlfeaturedescription/sequenceconstraint)
- [MLSequenceConstraint](/documentation/coreml/mlsequenceconstraint)

###### Accessing the constraints

- [var valueDescription: MLFeatureDescription](/documentation/coreml/mlsequenceconstraint/valuedescription)
- [var countRange: NSRange](/documentation/coreml/mlsequenceconstraint/countrange)

#### Accessing metadata

- [var classLabels: [Any]?](/documentation/coreml/mlmodeldescription/classlabels)
- [var metadata: [MLModelMetadataKey : Any]](/documentation/coreml/mlmodeldescription/metadata)
- [MLModelMetadataKey](/documentation/coreml/mlmodelmetadatakey)

##### Metadata keys

- [static let author: MLModelMetadataKey](/documentation/coreml/mlmodelmetadatakey/author)
- [static let description: MLModelMetadataKey](/documentation/coreml/mlmodelmetadatakey/description)
- [static let license: MLModelMetadataKey](/documentation/coreml/mlmodelmetadatakey/license)
- [static let versionString: MLModelMetadataKey](/documentation/coreml/mlmodelmetadatakey/versionstring)
- [static let creatorDefinedKey: MLModelMetadataKey](/documentation/coreml/mlmodelmetadatakey/creatordefinedkey)

##### Creating metadata

- [init(rawValue: String)](/documentation/coreml/mlmodelmetadatakey/init(rawvalue:))

#### Accessing prediction names

- [var predictedFeatureName: String?](/documentation/coreml/mlmodeldescription/predictedfeaturename)
- [var predictedProbabilitiesName: String?](/documentation/coreml/mlmodeldescription/predictedprobabilitiesname)

#### Accessing update descriptions

- [var isUpdatable: Bool](/documentation/coreml/mlmodeldescription/isupdatable)
- [var trainingInputDescriptionsByName: [String : MLFeatureDescription]](/documentation/coreml/mlmodeldescription/traininginputdescriptionsbyname)
- [var parameterDescriptionsByKey: [MLParameterKey : MLParameterDescription]](/documentation/coreml/mlmodeldescription/parameterdescriptionsbykey)
- [MLParameterDescription](/documentation/coreml/mlparameterdescription)

##### Describing the model parameter

- [var defaultValue: Any](/documentation/coreml/mlparameterdescription/defaultvalue)
- [var key: MLParameterKey](/documentation/coreml/mlparameterdescription/key)

##### Constraining numeric values

- [var numericConstraint: MLNumericConstraint?](/documentation/coreml/mlparameterdescription/numericconstraint)
- [MLNumericConstraint](/documentation/coreml/mlnumericconstraint)

###### Numeric Constraints

- [var minNumber: NSNumber](/documentation/coreml/mlnumericconstraint/minnumber)
- [var maxNumber: NSNumber](/documentation/coreml/mlnumericconstraint/maxnumber)
- [var enumeratedNumbers: Set<NSNumber>?](/documentation/coreml/mlnumericconstraint/enumeratednumbers)
- [func parameterValue(for: MLParameterKey) throws -> Any](/documentation/coreml/mlmodel/parametervalue(for:))
- [MLParameterKey](/documentation/coreml/mlparameterkey)

#### Scoping parameter keys

- [func scoped(to: String) -> MLParameterKey](/documentation/coreml/mlparameterkey/scoped(to:))

#### Accessing model parameters

- [class var numberOfNeighbors: MLParameterKey](/documentation/coreml/mlparameterkey/numberofneighbors)
- [class var linkedModelFileName: MLParameterKey](/documentation/coreml/mlparameterkey/linkedmodelfilename)
- [class var linkedModelSearchPath: MLParameterKey](/documentation/coreml/mlparameterkey/linkedmodelsearchpath)

#### Accessing neural network layer parameters

- [class var weights: MLParameterKey](/documentation/coreml/mlparameterkey/weights)
- [class var biases: MLParameterKey](/documentation/coreml/mlparameterkey/biases)

#### Accessing model update parameters

- [class var learningRate: MLParameterKey](/documentation/coreml/mlparameterkey/learningrate)
- [class var momentum: MLParameterKey](/documentation/coreml/mlparameterkey/momentum)
- [class var miniBatchSize: MLParameterKey](/documentation/coreml/mlparameterkey/minibatchsize)
- [class var beta1: MLParameterKey](/documentation/coreml/mlparameterkey/beta1)
- [class var beta2: MLParameterKey](/documentation/coreml/mlparameterkey/beta2)
- [class var eps: MLParameterKey](/documentation/coreml/mlparameterkey/eps)
- [class var epochs: MLParameterKey](/documentation/coreml/mlparameterkey/epochs)
- [class var shuffle: MLParameterKey](/documentation/coreml/mlparameterkey/shuffle)
- [class var seed: MLParameterKey](/documentation/coreml/mlparameterkey/seed)

### Supporting types

- [MLModelConfiguration](/documentation/coreml/mlmodelconfiguration)

#### Configuring model parameters

- [var functionName: String?](/documentation/coreml/mlmodelconfiguration/functionname)
- [var modelDisplayName: String?](/documentation/coreml/mlmodelconfiguration/modeldisplayname)
- [var parameters: [MLParameterKey : Any]?](/documentation/coreml/mlmodelconfiguration/parameters)
- [MLParameterKey](/documentation/coreml/mlparameterkey)

##### Scoping parameter keys

- [func scoped(to: String) -> MLParameterKey](/documentation/coreml/mlparameterkey/scoped(to:))

##### Accessing model parameters

- [class var numberOfNeighbors: MLParameterKey](/documentation/coreml/mlparameterkey/numberofneighbors)
- [class var linkedModelFileName: MLParameterKey](/documentation/coreml/mlparameterkey/linkedmodelfilename)
- [class var linkedModelSearchPath: MLParameterKey](/documentation/coreml/mlparameterkey/linkedmodelsearchpath)

##### Accessing neural network layer parameters

- [class var weights: MLParameterKey](/documentation/coreml/mlparameterkey/weights)
- [class var biases: MLParameterKey](/documentation/coreml/mlparameterkey/biases)

##### Accessing model update parameters

- [class var learningRate: MLParameterKey](/documentation/coreml/mlparameterkey/learningrate)
- [class var momentum: MLParameterKey](/documentation/coreml/mlparameterkey/momentum)
- [class var miniBatchSize: MLParameterKey](/documentation/coreml/mlparameterkey/minibatchsize)
- [class var beta1: MLParameterKey](/documentation/coreml/mlparameterkey/beta1)
- [class var beta2: MLParameterKey](/documentation/coreml/mlparameterkey/beta2)
- [class var eps: MLParameterKey](/documentation/coreml/mlparameterkey/eps)
- [class var epochs: MLParameterKey](/documentation/coreml/mlparameterkey/epochs)
- [class var shuffle: MLParameterKey](/documentation/coreml/mlparameterkey/shuffle)
- [class var seed: MLParameterKey](/documentation/coreml/mlparameterkey/seed)

#### Configuring GPU usage

- [var preferredMetalDevice: (any MTLDevice)?](/documentation/coreml/mlmodelconfiguration/preferredmetaldevice)
- [var allowLowPrecisionAccumulationOnGPU: Bool](/documentation/coreml/mlmodelconfiguration/allowlowprecisionaccumulationongpu)

#### Allowing access to processing units

- [var computeUnits: MLComputeUnits](/documentation/coreml/mlmodelconfiguration/computeunits)
- [MLComputeUnits](/documentation/coreml/mlcomputeunits)

##### Processing Unit Configurations

- [case all](/documentation/coreml/mlcomputeunits/all)
- [case cpuOnly](/documentation/coreml/mlcomputeunits/cpuonly)
- [case cpuAndGPU](/documentation/coreml/mlcomputeunits/cpuandgpu)
- [case cpuAndNeuralEngine](/documentation/coreml/mlcomputeunits/cpuandneuralengine)

##### Creating compute units

- [init?(rawValue: Int)](/documentation/coreml/mlcomputeunits/init(rawvalue:))

#### Getting optimization hints

- [var optimizationHints: MLOptimizationHints](/documentation/coreml/mlmodelconfiguration/optimizationhints-1oq0g)
- [MLOptimizationHints](/documentation/coreml/mloptimizationhints-swift.struct)

#### Creating optimization hints

- [init()](/documentation/coreml/mloptimizationhints-swift.struct/init())

#### Getting the reshape frequency

- [var reshapeFrequency: MLOptimizationHints.ReshapeFrequency](/documentation/coreml/mloptimizationhints-swift.struct/reshapefrequency-swift.property)
- [MLOptimizationHints.ReshapeFrequency](/documentation/coreml/mloptimizationhints-swift.struct/reshapefrequency-swift.enum)

##### Enumeration Cases

- [case frequent](/documentation/coreml/mloptimizationhints-swift.struct/reshapefrequency-swift.enum/frequent)
- [case infrequent](/documentation/coreml/mloptimizationhints-swift.struct/reshapefrequency-swift.enum/infrequent)

#### Getting the specialization strategy

- [var specializationStrategy: MLOptimizationHints.SpecializationStrategy](/documentation/coreml/mloptimizationhints-swift.struct/specializationstrategy-swift.property)
- [MLOptimizationHints.SpecializationStrategy](/documentation/coreml/mloptimizationhints-swift.struct/specializationstrategy-swift.enum)

##### Specialization strategies

- [case `default`](/documentation/coreml/mloptimizationhints-swift.struct/specializationstrategy-swift.enum/default)
- [case fastPrediction](/documentation/coreml/mloptimizationhints-swift.struct/specializationstrategy-swift.enum/fastprediction)
- [MLKey](/documentation/coreml/mlkey)

#### Retrieving a key’s information

- [var name: String](/documentation/coreml/mlkey/name)
- [var scope: String?](/documentation/coreml/mlkey/scope)
- [Model Customization](/documentation/coreml/model-customization)

### Model file size

- [Reducing the Size of Your Core ML App](/documentation/coreml/reducing-the-size-of-your-core-ml-app)

### Custom model layers

- [Creating and Integrating a Model with Custom Layers](/documentation/coreml/creating-and-integrating-a-model-with-custom-layers)
- [MLCustomLayer](/documentation/coreml/mlcustomlayer)

#### Creating a layer

- [init(parameters: [String : Any]) throws](/documentation/coreml/mlcustomlayer/init(parameters:))

#### Integrating a layer

- [func setWeightData([Data]) throws](/documentation/coreml/mlcustomlayer/setweightdata(_:))
- [func outputShapes(forInputShapes: [[NSNumber]]) throws -> [[NSNumber]]](/documentation/coreml/mlcustomlayer/outputshapes(forinputshapes:))

#### Evaluating a layer

- [func evaluate(inputs: [MLMultiArray], outputs: [MLMultiArray]) throws](/documentation/coreml/mlcustomlayer/evaluate(inputs:outputs:))
- [func encode(commandBuffer: any MTLCommandBuffer, inputs: [any MTLTexture], outputs: [any MTLTexture]) throws](/documentation/coreml/mlcustomlayer/encode(commandbuffer:inputs:outputs:))

### Custom models

- [MLCustomModel](/documentation/coreml/mlcustommodel)

#### Creating the model

- [init(modelDescription: MLModelDescription, parameters: [String : Any]) throws](/documentation/coreml/mlcustommodel/init(modeldescription:parameters:))

#### Making predictions

- [func prediction(from: any MLFeatureProvider, options: MLPredictionOptions) throws -> any MLFeatureProvider](/documentation/coreml/mlcustommodel/prediction(from:options:))
- [func predictions(from: any MLBatchProvider, options: MLPredictionOptions) throws -> any MLBatchProvider](/documentation/coreml/mlcustommodel/predictions(from:options:))
- [Model Personalization](/documentation/coreml/model-personalization)

### On-device model updates

- [MLTask](/documentation/coreml/mltask)

#### Identifying a task

- [var taskIdentifier: String](/documentation/coreml/mltask/taskidentifier)

#### Starting and stopping a task

- [func resume()](/documentation/coreml/mltask/resume())
- [func cancel()](/documentation/coreml/mltask/cancel())

#### Checking the state of a task

- [var state: MLTaskState](/documentation/coreml/mltask/state)
- [MLTaskState](/documentation/coreml/mltaskstate)

##### Transient states

- [case running](/documentation/coreml/mltaskstate/running)
- [case suspended](/documentation/coreml/mltaskstate/suspended)
- [case cancelling](/documentation/coreml/mltaskstate/cancelling)

##### Final states

- [case completed](/documentation/coreml/mltaskstate/completed)
- [case failed](/documentation/coreml/mltaskstate/failed)

##### Creating a task state

- [init?(rawValue: Int)](/documentation/coreml/mltaskstate/init(rawvalue:))
- [var error: (any Error)?](/documentation/coreml/mltask/error)
- [Personalizing a Model with On-Device Updates](/documentation/coreml/personalizing-a-model-with-on-device-updates)
- [MLUpdateTask](/documentation/coreml/mlupdatetask)

#### Creating an update task

- [convenience init(forModelAt: URL, trainingData: any MLBatchProvider, completionHandler: (MLUpdateContext) -> Void) throws](/documentation/coreml/mlupdatetask/init(formodelat:trainingdata:completionhandler:))
- [convenience init(forModelAt: URL, trainingData: any MLBatchProvider, progressHandlers: MLUpdateProgressHandlers) throws](/documentation/coreml/mlupdatetask/init(formodelat:trainingdata:progresshandlers:))
- [convenience init(forModelAt: URL, trainingData: any MLBatchProvider, configuration: MLModelConfiguration?, completionHandler: (MLUpdateContext) -> Void) throws](/documentation/coreml/mlupdatetask/init(formodelat:trainingdata:configuration:completionhandler:))
- [convenience init(forModelAt: URL, trainingData: any MLBatchProvider, configuration: MLModelConfiguration?, progressHandlers: MLUpdateProgressHandlers) throws](/documentation/coreml/mlupdatetask/init(formodelat:trainingdata:configuration:progresshandlers:))
- [convenience init(forModelAtURL: URL, trainingData: any MLBatchProvider, completionHandler: (MLUpdateContext) -> Void) throws](/documentation/coreml/mlupdatetask/init(formodelaturl:trainingdata:completionhandler:))
- [convenience init(forModelAtURL: URL, trainingData: any MLBatchProvider, progressHandlers: MLUpdateProgressHandlers) throws](/documentation/coreml/mlupdatetask/init(formodelaturl:trainingdata:progresshandlers:))
- [convenience init(forModelAtURL: URL, trainingData: any MLBatchProvider, configuration: MLModelConfiguration?, completionHandler: (MLUpdateContext) -> Void) throws](/documentation/coreml/mlupdatetask/init(formodelaturl:trainingdata:configuration:completionhandler:))
- [convenience init(forModelAtURL: URL, trainingData: any MLBatchProvider, configuration: MLModelConfiguration?, progressHandlers: MLUpdateProgressHandlers) throws](/documentation/coreml/mlupdatetask/init(formodelaturl:trainingdata:configuration:progresshandlers:))
- [MLBatchProvider](/documentation/coreml/mlbatchprovider)

##### Accessing values

- [func features(at: Int) -> any MLFeatureProvider](/documentation/coreml/mlbatchprovider/features(at:))
- [var count: Int](/documentation/coreml/mlbatchprovider/count)
- [MLModelConfiguration](/documentation/coreml/mlmodelconfiguration)

##### Configuring model parameters

- [var functionName: String?](/documentation/coreml/mlmodelconfiguration/functionname)
- [var modelDisplayName: String?](/documentation/coreml/mlmodelconfiguration/modeldisplayname)
- [var parameters: [MLParameterKey : Any]?](/documentation/coreml/mlmodelconfiguration/parameters)
- [MLParameterKey](/documentation/coreml/mlparameterkey)

###### Scoping parameter keys

- [func scoped(to: String) -> MLParameterKey](/documentation/coreml/mlparameterkey/scoped(to:))

###### Accessing model parameters

- [class var numberOfNeighbors: MLParameterKey](/documentation/coreml/mlparameterkey/numberofneighbors)
- [class var linkedModelFileName: MLParameterKey](/documentation/coreml/mlparameterkey/linkedmodelfilename)
- [class var linkedModelSearchPath: MLParameterKey](/documentation/coreml/mlparameterkey/linkedmodelsearchpath)

###### Accessing neural network layer parameters

- [class var weights: MLParameterKey](/documentation/coreml/mlparameterkey/weights)
- [class var biases: MLParameterKey](/documentation/coreml/mlparameterkey/biases)

###### Accessing model update parameters

- [class var learningRate: MLParameterKey](/documentation/coreml/mlparameterkey/learningrate)
- [class var momentum: MLParameterKey](/documentation/coreml/mlparameterkey/momentum)
- [class var miniBatchSize: MLParameterKey](/documentation/coreml/mlparameterkey/minibatchsize)
- [class var beta1: MLParameterKey](/documentation/coreml/mlparameterkey/beta1)
- [class var beta2: MLParameterKey](/documentation/coreml/mlparameterkey/beta2)
- [class var eps: MLParameterKey](/documentation/coreml/mlparameterkey/eps)
- [class var epochs: MLParameterKey](/documentation/coreml/mlparameterkey/epochs)
- [class var shuffle: MLParameterKey](/documentation/coreml/mlparameterkey/shuffle)
- [class var seed: MLParameterKey](/documentation/coreml/mlparameterkey/seed)

##### Configuring GPU usage

- [var preferredMetalDevice: (any MTLDevice)?](/documentation/coreml/mlmodelconfiguration/preferredmetaldevice)
- [var allowLowPrecisionAccumulationOnGPU: Bool](/documentation/coreml/mlmodelconfiguration/allowlowprecisionaccumulationongpu)

##### Allowing access to processing units

- [var computeUnits: MLComputeUnits](/documentation/coreml/mlmodelconfiguration/computeunits)
- [MLComputeUnits](/documentation/coreml/mlcomputeunits)

###### Processing Unit Configurations

- [case all](/documentation/coreml/mlcomputeunits/all)
- [case cpuOnly](/documentation/coreml/mlcomputeunits/cpuonly)
- [case cpuAndGPU](/documentation/coreml/mlcomputeunits/cpuandgpu)
- [case cpuAndNeuralEngine](/documentation/coreml/mlcomputeunits/cpuandneuralengine)

###### Creating compute units

- [init?(rawValue: Int)](/documentation/coreml/mlcomputeunits/init(rawvalue:))

##### Getting optimization hints

- [var optimizationHints: MLOptimizationHints](/documentation/coreml/mlmodelconfiguration/optimizationhints-1oq0g)
- [MLUpdateContext](/documentation/coreml/mlupdatecontext)

##### Getting the update context

- [var event: MLUpdateProgressEvent](/documentation/coreml/mlupdatecontext/event)
- [MLUpdateProgressEvent](/documentation/coreml/mlupdateprogressevent)

###### Getting progress event types

- [static var trainingBegin: MLUpdateProgressEvent](/documentation/coreml/mlupdateprogressevent/trainingbegin)
- [static var miniBatchEnd: MLUpdateProgressEvent](/documentation/coreml/mlupdateprogressevent/minibatchend)
- [static var epochEnd: MLUpdateProgressEvent](/documentation/coreml/mlupdateprogressevent/epochend)

###### Creating a progress event

- [init(rawValue: Int)](/documentation/coreml/mlupdateprogressevent/init(rawvalue:))
- [var task: MLUpdateTask](/documentation/coreml/mlupdatecontext/task)
- [var parameters: [MLParameterKey : Any]](/documentation/coreml/mlupdatecontext/parameters)
- [MLParameterKey](/documentation/coreml/mlparameterkey)

###### Scoping parameter keys

- [func scoped(to: String) -> MLParameterKey](/documentation/coreml/mlparameterkey/scoped(to:))

###### Accessing model parameters

- [class var numberOfNeighbors: MLParameterKey](/documentation/coreml/mlparameterkey/numberofneighbors)
- [class var linkedModelFileName: MLParameterKey](/documentation/coreml/mlparameterkey/linkedmodelfilename)
- [class var linkedModelSearchPath: MLParameterKey](/documentation/coreml/mlparameterkey/linkedmodelsearchpath)

###### Accessing neural network layer parameters

- [class var weights: MLParameterKey](/documentation/coreml/mlparameterkey/weights)
- [class var biases: MLParameterKey](/documentation/coreml/mlparameterkey/biases)

###### Accessing model update parameters

- [class var learningRate: MLParameterKey](/documentation/coreml/mlparameterkey/learningrate)
- [class var momentum: MLParameterKey](/documentation/coreml/mlparameterkey/momentum)
- [class var miniBatchSize: MLParameterKey](/documentation/coreml/mlparameterkey/minibatchsize)
- [class var beta1: MLParameterKey](/documentation/coreml/mlparameterkey/beta1)
- [class var beta2: MLParameterKey](/documentation/coreml/mlparameterkey/beta2)
- [class var eps: MLParameterKey](/documentation/coreml/mlparameterkey/eps)
- [class var epochs: MLParameterKey](/documentation/coreml/mlparameterkey/epochs)
- [class var shuffle: MLParameterKey](/documentation/coreml/mlparameterkey/shuffle)
- [class var seed: MLParameterKey](/documentation/coreml/mlparameterkey/seed)

##### Evaluating the update

- [var metrics: [MLMetricKey : Any]](/documentation/coreml/mlupdatecontext/metrics)
- [MLMetricKey](/documentation/coreml/mlmetrickey)

###### Getting the keys

- [class var lossValue: MLMetricKey](/documentation/coreml/mlmetrickey/lossvalue)
- [class var epochIndex: MLMetricKey](/documentation/coreml/mlmetrickey/epochindex)
- [class var miniBatchIndex: MLMetricKey](/documentation/coreml/mlmetrickey/minibatchindex)

###### Supporting types

- [MLKey](/documentation/coreml/mlkey)

###### Retrieving a key’s information

- [var name: String](/documentation/coreml/mlkey/name)
- [var scope: String?](/documentation/coreml/mlkey/scope)

##### Saving an updated model

- [var model: any MLModel & MLWritable](/documentation/coreml/mlupdatecontext/model)
- [MLWritable](/documentation/coreml/mlwritable)

###### Saving to a file

- [func write(to: URL) throws](/documentation/coreml/mlwritable/write(to:))
- [MLUpdateProgressHandlers](/documentation/coreml/mlupdateprogresshandlers)

##### Creating progress handlers

- [init(forEvents: MLUpdateProgressEvent, progressHandler: ((MLUpdateContext) -> Void)?, completionHandler: (MLUpdateContext) -> Void)](/documentation/coreml/mlupdateprogresshandlers/init(forevents:progresshandler:completionhandler:))
- [MLUpdateProgressEvent](/documentation/coreml/mlupdateprogressevent)

###### Getting progress event types

- [static var trainingBegin: MLUpdateProgressEvent](/documentation/coreml/mlupdateprogressevent/trainingbegin)
- [static var miniBatchEnd: MLUpdateProgressEvent](/documentation/coreml/mlupdateprogressevent/minibatchend)
- [static var epochEnd: MLUpdateProgressEvent](/documentation/coreml/mlupdateprogressevent/epochend)

###### Creating a progress event

- [init(rawValue: Int)](/documentation/coreml/mlupdateprogressevent/init(rawvalue:))
- [MLUpdateContext](/documentation/coreml/mlupdatecontext)

###### Getting the update context

- [var event: MLUpdateProgressEvent](/documentation/coreml/mlupdatecontext/event)
- [MLUpdateProgressEvent](/documentation/coreml/mlupdateprogressevent)

###### Getting progress event types

- [static var trainingBegin: MLUpdateProgressEvent](/documentation/coreml/mlupdateprogressevent/trainingbegin)
- [static var miniBatchEnd: MLUpdateProgressEvent](/documentation/coreml/mlupdateprogressevent/minibatchend)
- [static var epochEnd: MLUpdateProgressEvent](/documentation/coreml/mlupdateprogressevent/epochend)

###### Creating a progress event

- [init(rawValue: Int)](/documentation/coreml/mlupdateprogressevent/init(rawvalue:))
- [var task: MLUpdateTask](/documentation/coreml/mlupdatecontext/task)
- [var parameters: [MLParameterKey : Any]](/documentation/coreml/mlupdatecontext/parameters)
- [MLParameterKey](/documentation/coreml/mlparameterkey)

###### Scoping parameter keys

- [func scoped(to: String) -> MLParameterKey](/documentation/coreml/mlparameterkey/scoped(to:))

###### Accessing model parameters

- [class var numberOfNeighbors: MLParameterKey](/documentation/coreml/mlparameterkey/numberofneighbors)
- [class var linkedModelFileName: MLParameterKey](/documentation/coreml/mlparameterkey/linkedmodelfilename)
- [class var linkedModelSearchPath: MLParameterKey](/documentation/coreml/mlparameterkey/linkedmodelsearchpath)

###### Accessing neural network layer parameters

- [class var weights: MLParameterKey](/documentation/coreml/mlparameterkey/weights)
- [class var biases: MLParameterKey](/documentation/coreml/mlparameterkey/biases)

###### Accessing model update parameters

- [class var learningRate: MLParameterKey](/documentation/coreml/mlparameterkey/learningrate)
- [class var momentum: MLParameterKey](/documentation/coreml/mlparameterkey/momentum)
- [class var miniBatchSize: MLParameterKey](/documentation/coreml/mlparameterkey/minibatchsize)
- [class var beta1: MLParameterKey](/documentation/coreml/mlparameterkey/beta1)
- [class var beta2: MLParameterKey](/documentation/coreml/mlparameterkey/beta2)
- [class var eps: MLParameterKey](/documentation/coreml/mlparameterkey/eps)
- [class var epochs: MLParameterKey](/documentation/coreml/mlparameterkey/epochs)
- [class var shuffle: MLParameterKey](/documentation/coreml/mlparameterkey/shuffle)
- [class var seed: MLParameterKey](/documentation/coreml/mlparameterkey/seed)

###### Evaluating the update

- [var metrics: [MLMetricKey : Any]](/documentation/coreml/mlupdatecontext/metrics)
- [MLMetricKey](/documentation/coreml/mlmetrickey)

###### Getting the keys

- [class var lossValue: MLMetricKey](/documentation/coreml/mlmetrickey/lossvalue)
- [class var epochIndex: MLMetricKey](/documentation/coreml/mlmetrickey/epochindex)
- [class var miniBatchIndex: MLMetricKey](/documentation/coreml/mlmetrickey/minibatchindex)

###### Supporting types

- [MLKey](/documentation/coreml/mlkey)

###### Retrieving a key’s information

- [var name: String](/documentation/coreml/mlkey/name)
- [var scope: String?](/documentation/coreml/mlkey/scope)

###### Saving an updated model

- [var model: any MLModel & MLWritable](/documentation/coreml/mlupdatecontext/model)
- [MLWritable](/documentation/coreml/mlwritable)

###### Saving to a file

- [func write(to: URL) throws](/documentation/coreml/mlwritable/write(to:))

#### Starting and Resuming an Update

- [func resume(withParameters: [MLParameterKey : Any])](/documentation/coreml/mlupdatetask/resume(withparameters:))
- [MLParameterKey](/documentation/coreml/mlparameterkey)

##### Scoping parameter keys

- [func scoped(to: String) -> MLParameterKey](/documentation/coreml/mlparameterkey/scoped(to:))

##### Accessing model parameters

- [class var numberOfNeighbors: MLParameterKey](/documentation/coreml/mlparameterkey/numberofneighbors)
- [class var linkedModelFileName: MLParameterKey](/documentation/coreml/mlparameterkey/linkedmodelfilename)
- [class var linkedModelSearchPath: MLParameterKey](/documentation/coreml/mlparameterkey/linkedmodelsearchpath)

##### Accessing neural network layer parameters

- [class var weights: MLParameterKey](/documentation/coreml/mlparameterkey/weights)
- [class var biases: MLParameterKey](/documentation/coreml/mlparameterkey/biases)

##### Accessing model update parameters

- [class var learningRate: MLParameterKey](/documentation/coreml/mlparameterkey/learningrate)
- [class var momentum: MLParameterKey](/documentation/coreml/mlparameterkey/momentum)
- [class var miniBatchSize: MLParameterKey](/documentation/coreml/mlparameterkey/minibatchsize)
- [class var beta1: MLParameterKey](/documentation/coreml/mlparameterkey/beta1)
- [class var beta2: MLParameterKey](/documentation/coreml/mlparameterkey/beta2)
- [class var eps: MLParameterKey](/documentation/coreml/mlparameterkey/eps)
- [class var epochs: MLParameterKey](/documentation/coreml/mlparameterkey/epochs)
- [class var shuffle: MLParameterKey](/documentation/coreml/mlparameterkey/shuffle)
- [class var seed: MLParameterKey](/documentation/coreml/mlparameterkey/seed)

## Model inputs and outputs

- [Making Predictions with a Sequence of Inputs](/documentation/coreml/making-predictions-with-a-sequence-of-inputs)
- [MLFeatureValue](/documentation/coreml/mlfeaturevalue)

### Creating a feature value

- [convenience init(MLSendableFeatureValue)](/documentation/coreml/mlfeaturevalue/init(_:))

### Creating numeric feature values

- [convenience init(int64: Int64)](/documentation/coreml/mlfeaturevalue/init(int64:))
- [convenience init(double: Double)](/documentation/coreml/mlfeaturevalue/init(double:))

### Creating string feature values

- [convenience init(string: String)](/documentation/coreml/mlfeaturevalue/init(string:))

### Creating multidimensional feature values

- [convenience init(multiArray: MLMultiArray)](/documentation/coreml/mlfeaturevalue/init(multiarray:))
- [convenience init<Scalar>(shapedArray: MLShapedArray<Scalar>)](/documentation/coreml/mlfeaturevalue/init(shapedarray:))

### Creating collection feature values

- [convenience init(dictionary: [AnyHashable : NSNumber]) throws](/documentation/coreml/mlfeaturevalue/init(dictionary:))
- [convenience init(sequence: MLSequence)](/documentation/coreml/mlfeaturevalue/init(sequence:))

### Creating image feature values

- [convenience init(pixelBuffer: CVPixelBuffer)](/documentation/coreml/mlfeaturevalue/init(pixelbuffer:))
- [convenience init(CGImage: CGImage, pixelsWide: Int, pixelsHigh: Int, pixelFormatType: OSType, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(cgimage:pixelswide:pixelshigh:pixelformattype:options:)-2zg43)
- [convenience init(CGImage: CGImage, orientation: CGImagePropertyOrientation, pixelsWide: Int, pixelsHigh: Int, pixelFormatType: OSType, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(cgimage:orientation:pixelswide:pixelshigh:pixelformattype:options:)-4nme0)
- [convenience init(CGImage: CGImage, constraint: MLImageConstraint, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(cgimage:constraint:options:)-1j00l)
- [convenience init(CGImage: CGImage, orientation: CGImagePropertyOrientation, constraint: MLImageConstraint, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(cgimage:orientation:constraint:options:)-87vk0)
- [convenience init(imageAtURL: URL, pixelsWide: Int, pixelsHigh: Int, pixelFormatType: OSType, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(imageaturl:pixelswide:pixelshigh:pixelformattype:options:))
- [convenience init(imageAtURL: URL, orientation: CGImagePropertyOrientation, pixelsWide: Int, pixelsHigh: Int, pixelFormatType: OSType, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(imageaturl:orientation:pixelswide:pixelshigh:pixelformattype:options:))
- [convenience init(imageAtURL: URL, constraint: MLImageConstraint, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(imageaturl:constraint:options:))
- [convenience init(imageAtURL: URL, orientation: CGImagePropertyOrientation, constraint: MLImageConstraint, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(imageaturl:orientation:constraint:options:))
- [MLImageConstraint](/documentation/coreml/mlimageconstraint)

#### Accessing the constraints

- [var pixelsWide: Int](/documentation/coreml/mlimageconstraint/pixelswide)
- [var pixelsHigh: Int](/documentation/coreml/mlimageconstraint/pixelshigh)
- [var pixelFormatType: OSType](/documentation/coreml/mlimageconstraint/pixelformattype)

#### Inspecting acceptable sizes

- [var sizeConstraint: MLImageSizeConstraint](/documentation/coreml/mlimageconstraint/sizeconstraint)
- [MLImageSizeConstraint](/documentation/coreml/mlimagesizeconstraint)

##### Determining relevant constraints

- [var type: MLImageSizeConstraintType](/documentation/coreml/mlimagesizeconstraint/type)
- [MLImageSizeConstraintType](/documentation/coreml/mlimagesizeconstrainttype)

###### Constraint types

- [case range](/documentation/coreml/mlimagesizeconstrainttype/range)
- [case enumerated](/documentation/coreml/mlimagesizeconstrainttype/enumerated)
- [case unspecified](/documentation/coreml/mlimagesizeconstrainttype/unspecified)

###### Creating a constraint type

- [init?(rawValue: Int)](/documentation/coreml/mlimagesizeconstrainttype/init(rawvalue:))

##### Accessing the image size ranges

- [var pixelsWideRange: NSRange](/documentation/coreml/mlimagesizeconstraint/pixelswiderange)
- [var pixelsHighRange: NSRange](/documentation/coreml/mlimagesizeconstraint/pixelshighrange)

##### Accessing the enumerated image sizes

- [var enumeratedImageSizes: [MLImageSize]](/documentation/coreml/mlimagesizeconstraint/enumeratedimagesizes)
- [MLImageSize](/documentation/coreml/mlimagesize)

###### Accessing an image size

- [var pixelsHigh: Int](/documentation/coreml/mlimagesize/pixelshigh)
- [var pixelsWide: Int](/documentation/coreml/mlimagesize/pixelswide)
- [MLFeatureValue.ImageOption](/documentation/coreml/mlfeaturevalue/imageoption)

#### Image options keys

- [static let cropRect: MLFeatureValue.ImageOption](/documentation/coreml/mlfeaturevalue/imageoption/croprect)
- [static let cropAndScale: MLFeatureValue.ImageOption](/documentation/coreml/mlfeaturevalue/imageoption/cropandscale)

#### Image option key initializers

- [init(String)](/documentation/coreml/mlfeaturevalue/imageoption/init(_:))
- [init(rawValue: String)](/documentation/coreml/mlfeaturevalue/imageoption/init(rawvalue:))

### Creating undefined feature values

- [convenience init(undefined: MLFeatureType)](/documentation/coreml/mlfeaturevalue/init(undefined:))

### Accessing the feature’s type

- [var type: MLFeatureType](/documentation/coreml/mlfeaturevalue/type)

### Accessing the feature’s value

- [var isUndefined: Bool](/documentation/coreml/mlfeaturevalue/isundefined)
- [var int64Value: Int64](/documentation/coreml/mlfeaturevalue/int64value)
- [var doubleValue: Double](/documentation/coreml/mlfeaturevalue/doublevalue)
- [var stringValue: String](/documentation/coreml/mlfeaturevalue/stringvalue)
- [var imageBufferValue: CVPixelBuffer?](/documentation/coreml/mlfeaturevalue/imagebuffervalue)
- [func shapedArrayValue<Scalar>(of: Scalar.Type) -> MLShapedArray<Scalar>?](/documentation/coreml/mlfeaturevalue/shapedarrayvalue(of:))
- [var multiArrayValue: MLMultiArray?](/documentation/coreml/mlfeaturevalue/multiarrayvalue)
- [var sequenceValue: MLSequence?](/documentation/coreml/mlfeaturevalue/sequencevalue)
- [var dictionaryValue: [AnyHashable : NSNumber]](/documentation/coreml/mlfeaturevalue/dictionaryvalue)

### Comparing feature values

- [func isEqual(to: MLFeatureValue) -> Bool](/documentation/coreml/mlfeaturevalue/isequal(to:))

### Supporting types

- [MLFeatureType](/documentation/coreml/mlfeaturetype)

#### Feature types

- [case int64](/documentation/coreml/mlfeaturetype/int64)
- [case double](/documentation/coreml/mlfeaturetype/double)
- [case image](/documentation/coreml/mlfeaturetype/image)
- [case multiArray](/documentation/coreml/mlfeaturetype/multiarray)
- [case string](/documentation/coreml/mlfeaturetype/string)
- [case dictionary](/documentation/coreml/mlfeaturetype/dictionary)
- [case sequence](/documentation/coreml/mlfeaturetype/sequence)
- [case state](/documentation/coreml/mlfeaturetype/state)
- [case invalid](/documentation/coreml/mlfeaturetype/invalid)

#### Creating a feature type

- [init?(rawValue: Int)](/documentation/coreml/mlfeaturetype/init(rawvalue:))
- [MLShapedArray](/documentation/coreml/mlshapedarray)

#### Creating a shaped array

- [init(scalar: Scalar)](/documentation/coreml/mlshapedarray/init(scalar:))
- [init<S>(scalars: S, shape: [Int])](/documentation/coreml/mlshapedarray/init(scalars:shape:))
- [init(mutating: CVPixelBuffer, shape: [Int])](/documentation/coreml/mlshapedarray/init(mutating:shape:))

#### Creating a shaped array from another type

- [init(MLMultiArray)](/documentation/coreml/mlshapedarray/init(_:))
- [init<S>(concatenating: S, alongAxis: Int)](/documentation/coreml/mlshapedarray/init(concatenating:alongaxis:))

#### Creating a shaped array with pointers to memory

- [init(unsafeUninitializedShape: [Int], initializingWith: (inout UnsafeMutableBufferPointer<Scalar>, [Int]) throws -> Void) rethrows](/documentation/coreml/mlshapedarray/init(unsafeuninitializedshape:initializingwith:))

#### Creating a shaped array from data

- [init(data: Data, shape: [Int])](/documentation/coreml/mlshapedarray/init(data:shape:))
- [init(data: Data, shape: [Int], strides: [Int])](/documentation/coreml/mlshapedarray/init(data:shape:strides:))

#### Shaping the array

- [func changingLayout(to: MLShapedArrayBufferLayout) -> MLShapedArray<Scalar>](/documentation/coreml/mlshapedarray/changinglayout(to:))
- [func expandingShape(at: Int) -> MLShapedArray<Scalar>](/documentation/coreml/mlshapedarray/expandingshape(at:))
- [func reshaped(to: [Int]) -> MLShapedArray<Scalar>](/documentation/coreml/mlshapedarray/reshaped(to:))
- [func squeezingShape() -> MLShapedArray<Scalar>](/documentation/coreml/mlshapedarray/squeezingshape())
- [func transposed() -> MLShapedArray<Scalar>](/documentation/coreml/mlshapedarray/transposed())
- [func transposed(permutation: [Int]) -> MLShapedArray<Scalar>](/documentation/coreml/mlshapedarray/transposed(permutation:))

#### Reading and writing the pixel buffer

- [func withMutablePixelBufferIfAvailable<R>((CVPixelBuffer) throws -> R) rethrows -> R?](/documentation/coreml/mlshapedarray/withmutablepixelbufferifavailable(_:))
- [func withPixelBufferIfAvailable<R>((CVPixelBuffer) throws -> R) rethrows -> R?](/documentation/coreml/mlshapedarray/withpixelbufferifavailable(_:))

#### Modifying a shaped array

- [func withUnsafeMutableShapedBufferPointer<R>(using: MLShapedArrayBufferLayout, (inout UnsafeMutableBufferPointer<Scalar>, [Int], [Int]) throws -> R) rethrows -> R](/documentation/coreml/mlshapedarray/withunsafemutableshapedbufferpointer(using:_:))

#### Encoding and decoding

- [init(from: any Decoder) throws](/documentation/coreml/mlshapedarray/init(from:))
- [func encode(to: any Encoder) throws](/documentation/coreml/mlshapedarray/encode(to:))

#### Default Implementations

- [CustomStringConvertible Implementations](/documentation/coreml/mlshapedarray/customstringconvertible-implementations)

##### Instance Properties

- [var description: String](/documentation/coreml/mlshapedarray/description)
- [Decodable Implementations](/documentation/coreml/mlshapedarray/decodable-implementations)

##### Initializers

- [init(from: any Decoder) throws](/documentation/coreml/mlshapedarray/init(from:))
- [Encodable Implementations](/documentation/coreml/mlshapedarray/encodable-implementations)

##### Instance Methods

- [func encode(to: any Encoder) throws](/documentation/coreml/mlshapedarray/encode(to:))
- [MLShapedArrayProtocol](/documentation/coreml/mlshapedarrayprotocol)

#### Creating a shaped array type

- [init<S>(scalars: S, shape: [Int])](/documentation/coreml/mlshapedarrayprotocol/init(scalars:shape:))
- [init(repeating: Self.Scalar, shape: [Int])](/documentation/coreml/mlshapedarrayprotocol/init(repeating:shape:))
- [init(identityMatrixOfSize:)](/documentation/coreml/mlshapedarrayprotocol/init(identitymatrixofsize:))
- [init(randomScalarsIn:shape:)](/documentation/coreml/mlshapedarrayprotocol/init(randomscalarsin:shape:))
- [init(bytesNoCopy: UnsafeRawPointer, shape: [Int], deallocator: Data.Deallocator)](/documentation/coreml/mlshapedarrayprotocol/init(bytesnocopy:shape:deallocator:))
- [init(bytesNoCopy: UnsafeRawPointer, shape: [Int], strides: [Int], deallocator: Data.Deallocator)](/documentation/coreml/mlshapedarrayprotocol/init(bytesnocopy:shape:strides:deallocator:))
- [init(unsafeUninitializedShape: [Int], initializingWith: (inout UnsafeMutableBufferPointer<Self.Scalar>, [Int]) throws -> Void) rethrows](/documentation/coreml/mlshapedarrayprotocol/init(unsafeuninitializedshape:initializingwith:))

#### Creating a shaped array type from another type

- [init(MLMultiArray)](/documentation/coreml/mlshapedarrayprotocol/init(_:))
- [init(converting:)](/documentation/coreml/mlshapedarrayprotocol/init(converting:))

#### Inspecting a shaped array type

- [var shape: [Int]](/documentation/coreml/mlshapedarrayprotocol/shape)
- [var strides: [Int]](/documentation/coreml/mlshapedarrayprotocol/strides)
- [var count: Int](/documentation/coreml/mlshapedarrayprotocol/count)
- [var isScalar: Bool](/documentation/coreml/mlshapedarrayprotocol/isscalar)
- [var scalarCount: Int](/documentation/coreml/mlshapedarrayprotocol/scalarcount)
- [var scalar: Self.Scalar?](/documentation/coreml/mlshapedarrayprotocol/scalar-swift.property)
- [var scalars: [Self.Scalar]](/documentation/coreml/mlshapedarrayprotocol/scalars)
- [func withUnsafeShapedBufferPointer<R>((UnsafeBufferPointer<Self.Scalar>, [Int], [Int]) throws -> R) rethrows -> R](/documentation/coreml/mlshapedarrayprotocol/withunsafeshapedbufferpointer(_:))

#### Accessing elements

- [subscript<C>(scalarAt _: C) -> Self.Scalar](/documentation/coreml/mlshapedarrayprotocol/subscript(scalarat:))
- [subscript(_:)](/documentation/coreml/mlshapedarrayprotocol/subscript(_:))

#### Modifying a shaped array type

- [func fill(with:)](/documentation/coreml/mlshapedarrayprotocol/fill(with:))
- [func withUnsafeMutableShapedBufferPointer<R>((inout UnsafeMutableBufferPointer<Self.Scalar>, [Int], [Int]) throws -> R) rethrows -> R](/documentation/coreml/mlshapedarrayprotocol/withunsafemutableshapedbufferpointer(_:))

#### Supporting types

- [Scalar](/documentation/coreml/mlshapedarrayprotocol/scalar-swift.associatedtype)
- [MLShapedArraySlice](/documentation/coreml/mlshapedarrayslice)

##### Creating a shaped array slice

- [init(scalar: Scalar)](/documentation/coreml/mlshapedarrayslice/init(scalar:))
- [init<S>(scalars: S, shape: [Int])](/documentation/coreml/mlshapedarrayslice/init(scalars:shape:))
- [init(mutating: CVPixelBuffer, shape: [Int])](/documentation/coreml/mlshapedarrayslice/init(mutating:shape:))

##### Creating a shaped array slice from another type

- [init(MLMultiArray)](/documentation/coreml/mlshapedarrayslice/init(_:))
- [init<S>(concatenating: S, alongAxis: Int)](/documentation/coreml/mlshapedarrayslice/init(concatenating:alongaxis:))

##### Creating a shaped array slice with pointers to memory

- [init(unsafeUninitializedShape: [Int], initializingWith: (inout UnsafeMutableBufferPointer<Scalar>, [Int]) throws -> Void) rethrows](/documentation/coreml/mlshapedarrayslice/init(unsafeuninitializedshape:initializingwith:))

##### Creating a shaped array slice with data

- [init(data: Data, shape: [Int])](/documentation/coreml/mlshapedarrayslice/init(data:shape:))
- [init(data: Data, shape: [Int], strides: [Int])](/documentation/coreml/mlshapedarrayslice/init(data:shape:strides:))

##### Shaping the array slice

- [func changingLayout(to: MLShapedArrayBufferLayout) -> MLShapedArraySlice<Scalar>](/documentation/coreml/mlshapedarrayslice/changinglayout(to:))
- [func expandingShape(at: Int) -> MLShapedArraySlice<Scalar>](/documentation/coreml/mlshapedarrayslice/expandingshape(at:))
- [func reshaped(to: [Int]) -> MLShapedArraySlice<Scalar>](/documentation/coreml/mlshapedarrayslice/reshaped(to:))
- [func squeezingShape() -> MLShapedArraySlice<Scalar>](/documentation/coreml/mlshapedarrayslice/squeezingshape())
- [func transposed() -> MLShapedArraySlice<Scalar>](/documentation/coreml/mlshapedarrayslice/transposed())
- [func transposed(permutation: [Int]) -> MLShapedArraySlice<Scalar>](/documentation/coreml/mlshapedarrayslice/transposed(permutation:))

##### Modifying a shaped array type

- [func withUnsafeMutableShapedBufferPointer<R>(using: MLShapedArrayBufferLayout, (inout UnsafeMutableBufferPointer<Scalar>, [Int], [Int]) throws -> R) rethrows -> R](/documentation/coreml/mlshapedarrayslice/withunsafemutableshapedbufferpointer(using:_:))

##### Encoding and decoding an array slice

- [init(from: any Decoder) throws](/documentation/coreml/mlshapedarrayslice/init(from:))
- [func encode(to: any Encoder) throws](/documentation/coreml/mlshapedarrayslice/encode(to:))

##### Default Implementations

- [Decodable Implementations](/documentation/coreml/mlshapedarrayslice/decodable-implementations)

###### Initializers

- [init(from: any Decoder) throws](/documentation/coreml/mlshapedarrayslice/init(from:))
- [Encodable Implementations](/documentation/coreml/mlshapedarrayslice/encodable-implementations)

###### Instance Methods

- [func encode(to: any Encoder) throws](/documentation/coreml/mlshapedarrayslice/encode(to:))
- [MLShapedArrayScalar](/documentation/coreml/mlshapedarrayscalar)

##### Determining the underlying type

- [static var multiArrayDataType: MLMultiArrayDataType](/documentation/coreml/mlshapedarrayscalar/multiarraydatatype)
- [MLShapedArrayRangeExpression](/documentation/coreml/mlshapedarrayrangeexpression)

##### Generating relative ranges

- [func relative(toShapedArrayAxis: Range<Int>) -> Range<Int>](/documentation/coreml/mlshapedarrayrangeexpression/relative(toshapedarrayaxis:))
- [MLMultiArray](/documentation/coreml/mlmultiarray)

#### Creating a multiarray

- [convenience(_:)](/documentation/coreml/mlmultiarray/init(_:))
- [init(shape: [NSNumber], dataType: MLMultiArrayDataType) throws](/documentation/coreml/mlmultiarray/init(shape:datatype:))
- [convenience init(shape: [Int], dataType: MLMultiArrayDataType, strides: [Int])](/documentation/coreml/mlmultiarray/init(shape:datatype:strides:))
- [init(dataPointer: UnsafeMutableRawPointer, shape: [NSNumber], dataType: MLMultiArrayDataType, strides: [NSNumber], deallocator: ((UnsafeMutableRawPointer) -> Void)?) throws](/documentation/coreml/mlmultiarray/init(datapointer:shape:datatype:strides:deallocator:))
- [convenience init(byConcatenatingMultiArrays: [MLMultiArray], alongAxis: Int, dataType: MLMultiArrayDataType)](/documentation/coreml/mlmultiarray/init(byconcatenatingmultiarrays:alongaxis:datatype:))
- [init(pixelBuffer: CVPixelBuffer, shape: [NSNumber])](/documentation/coreml/mlmultiarray/init(pixelbuffer:shape:))
- [MLMultiArrayDataType](/documentation/coreml/mlmultiarraydatatype)

##### Multiarray data types

- [case int8](/documentation/coreml/mlmultiarraydatatype/int8)
- [case int32](/documentation/coreml/mlmultiarraydatatype/int32)
- [case float16](/documentation/coreml/mlmultiarraydatatype/float16)
- [case float32](/documentation/coreml/mlmultiarraydatatype/float32)
- [case double](/documentation/coreml/mlmultiarraydatatype/double)
- [static var float: MLMultiArrayDataType](/documentation/coreml/mlmultiarraydatatype/float)
- [static var float64: MLMultiArrayDataType](/documentation/coreml/mlmultiarraydatatype/float64)

##### Creating a multiarray data type

- [init?(rawValue: Int)](/documentation/coreml/mlmultiarraydatatype/init(rawvalue:))

#### Inspecting a multiarray

- [var count: Int](/documentation/coreml/mlmultiarray/count)
- [var dataType: MLMultiArrayDataType](/documentation/coreml/mlmultiarray/datatype)
- [var shape: [NSNumber]](/documentation/coreml/mlmultiarray/shape)
- [var strides: [NSNumber]](/documentation/coreml/mlmultiarray/strides)

#### Transfering the contents

- [func transfer(to: MLMultiArray)](/documentation/coreml/mlmultiarray/transfer(to:))

#### Providing buffer access

- [func withUnsafeBufferPointer<S, R>(ofType: S.Type, (UnsafeBufferPointer<S>) throws -> R) rethrows -> R](/documentation/coreml/mlmultiarray/withunsafebufferpointer(oftype:_:))
- [func withUnsafeBytes<R>((UnsafeRawBufferPointer) throws -> R) rethrows -> R](/documentation/coreml/mlmultiarray/withunsafebytes(_:))
- [func withUnsafeMutableBufferPointer<S, R>(ofType: S.Type, (UnsafeMutableBufferPointer<S>, [Int]) throws -> R) rethrows -> R](/documentation/coreml/mlmultiarray/withunsafemutablebufferpointer(oftype:_:))
- [func withUnsafeMutableBytes<R>((UnsafeMutableRawBufferPointer, [Int]) throws -> R) rethrows -> R](/documentation/coreml/mlmultiarray/withunsafemutablebytes(_:))

#### Accessing a multiarray’s elements

- [subscript(_:)](/documentation/coreml/mlmultiarray/subscript(_:))
- [var pixelBuffer: CVPixelBuffer?](/documentation/coreml/mlmultiarray/pixelbuffer)
- [var dataPointer: UnsafeMutableRawPointer](/documentation/coreml/mlmultiarray/datapointer)

#### Initializers

- [convenience init(concatenating: [MLMultiArray], axis: Int, dataType: MLMultiArrayDataType)](/documentation/coreml/mlmultiarray/init(concatenating:axis:datatype:))

#### Default Implementations

- [MLMultiArray Implementations](/documentation/coreml/mlmultiarray/mlmultiarray-implementations)

##### Initializers

- [convenience init(byConcatenatingMultiArrays: [MLMultiArray], alongAxis: Int, dataType: MLMultiArrayDataType)](/documentation/coreml/mlmultiarray/init(byconcatenatingmultiarrays:alongaxis:datatype:))
- [MLSequence](/documentation/coreml/mlsequence)

#### Creating a sequence

- [convenience init(strings: [String])](/documentation/coreml/mlsequence/init(strings:))
- [convenience init(int64s: [NSNumber])](/documentation/coreml/mlsequence/init(int64s:))
- [convenience init(empty: MLFeatureType)](/documentation/coreml/mlsequence/init(empty:))

#### Identifying the sequence’s element type

- [var type: MLFeatureType](/documentation/coreml/mlsequence/type)

#### Retrieving the Sequence’s Values

- [var stringValues: [String]](/documentation/coreml/mlsequence/stringvalues)
- [var int64Values: [NSNumber]](/documentation/coreml/mlsequence/int64values)

### Initializers

- [convenience init(cgImage: CGImage, constraint: MLImageConstraint, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(cgimage:constraint:options:))
- [convenience init(cgImage: CGImage, orientation: CGImagePropertyOrientation, constraint: MLImageConstraint, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(cgimage:orientation:constraint:options:))
- [convenience init(cgImage: CGImage, orientation: CGImagePropertyOrientation, pixelsWide: Int, pixelsHigh: Int, pixelFormatType: OSType, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(cgimage:orientation:pixelswide:pixelshigh:pixelformattype:options:))
- [convenience init(cgImage: CGImage, pixelsWide: Int, pixelsHigh: Int, pixelFormatType: OSType, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(cgimage:pixelswide:pixelshigh:pixelformattype:options:))
- [convenience init(imageAt: URL, constraint: MLImageConstraint, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(imageat:constraint:options:))
- [convenience init(imageAt: URL, orientation: CGImagePropertyOrientation, constraint: MLImageConstraint, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(imageat:orientation:constraint:options:))
- [convenience init(imageAt: URL, orientation: CGImagePropertyOrientation, pixelsWide: Int, pixelsHigh: Int, pixelFormatType: OSType, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(imageat:orientation:pixelswide:pixelshigh:pixelformattype:options:))
- [convenience init(imageAt: URL, pixelsWide: Int, pixelsHigh: Int, pixelFormatType: OSType, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(imageat:pixelswide:pixelshigh:pixelformattype:options:))

### Default Implementations

- [MLFeatureValue Implementations](/documentation/coreml/mlfeaturevalue/mlfeaturevalue-implementations)

#### Initializers

- [convenience init(CGImage: CGImage, constraint: MLImageConstraint, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(cgimage:constraint:options:)-1j00l)
- [convenience init(CGImage: CGImage, orientation: CGImagePropertyOrientation, constraint: MLImageConstraint, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(cgimage:orientation:constraint:options:)-87vk0)
- [convenience init(CGImage: CGImage, orientation: CGImagePropertyOrientation, pixelsWide: Int, pixelsHigh: Int, pixelFormatType: OSType, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(cgimage:orientation:pixelswide:pixelshigh:pixelformattype:options:)-4nme0)
- [convenience init(CGImage: CGImage, pixelsWide: Int, pixelsHigh: Int, pixelFormatType: OSType, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(cgimage:pixelswide:pixelshigh:pixelformattype:options:)-2zg43)
- [convenience init(imageAtURL: URL, constraint: MLImageConstraint, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(imageaturl:constraint:options:))
- [convenience init(imageAtURL: URL, orientation: CGImagePropertyOrientation, constraint: MLImageConstraint, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(imageaturl:orientation:constraint:options:))
- [convenience init(imageAtURL: URL, orientation: CGImagePropertyOrientation, pixelsWide: Int, pixelsHigh: Int, pixelFormatType: OSType, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(imageaturl:orientation:pixelswide:pixelshigh:pixelformattype:options:))
- [convenience init(imageAtURL: URL, pixelsWide: Int, pixelsHigh: Int, pixelFormatType: OSType, options: [MLFeatureValue.ImageOption : Any]?) throws](/documentation/coreml/mlfeaturevalue/init(imageaturl:pixelswide:pixelshigh:pixelformattype:options:))
- [MLSendableFeatureValue](/documentation/coreml/mlsendablefeaturevalue)

### Creating a sendable feature value

- [init(_:)](/documentation/coreml/mlsendablefeaturevalue/init(_:))
- [init(undefined: MLFeatureType)](/documentation/coreml/mlsendablefeaturevalue/init(undefined:))

### Accessing the values

- [var doubleValue: Double?](/documentation/coreml/mlsendablefeaturevalue/doublevalue)
- [var float16Value: Float16?](/documentation/coreml/mlsendablefeaturevalue/float16value)
- [var floatValue: Float?](/documentation/coreml/mlsendablefeaturevalue/floatvalue)
- [var integerDictionaryValue: [Int : Double]?](/documentation/coreml/mlsendablefeaturevalue/integerdictionaryvalue)
- [var integerValue: Int?](/documentation/coreml/mlsendablefeaturevalue/integervalue)
- [var isScalar: Bool](/documentation/coreml/mlsendablefeaturevalue/isscalar)
- [var isShapedArray: Bool](/documentation/coreml/mlsendablefeaturevalue/isshapedarray)
- [var isUndefined: Bool](/documentation/coreml/mlsendablefeaturevalue/isundefined)
- [var stringArrayValue: [String]?](/documentation/coreml/mlsendablefeaturevalue/stringarrayvalue)
- [var stringDictionaryValue: [String : Double]?](/documentation/coreml/mlsendablefeaturevalue/stringdictionaryvalue)
- [var stringValue: String?](/documentation/coreml/mlsendablefeaturevalue/stringvalue)
- [var type: MLFeatureType](/documentation/coreml/mlsendablefeaturevalue/type)

### Getting the shaped array value

- [func shapedArrayValue<Scalar>(of: Scalar.Type) -> MLShapedArray<Scalar>?](/documentation/coreml/mlsendablefeaturevalue/shapedarrayvalue(of:))
- [MLFeatureProvider](/documentation/coreml/mlfeatureprovider)

### Accessing values

- [func featureValue(for: String) -> MLFeatureValue?](/documentation/coreml/mlfeatureprovider/featurevalue(for:))
- [var featureNames: Set<String>](/documentation/coreml/mlfeatureprovider/featurenames)
- [MLDictionaryFeatureProvider](/documentation/coreml/mldictionaryfeatureprovider)

### Creating the provider

- [init(dictionary: [String : Any]) throws](/documentation/coreml/mldictionaryfeatureprovider/init(dictionary:))

### Accessing the features

- [subscript(String) -> MLFeatureValue?](/documentation/coreml/mldictionaryfeatureprovider/subscript(_:))
- [var dictionary: [String : MLFeatureValue]](/documentation/coreml/mldictionaryfeatureprovider/dictionary)
- [MLBatchProvider](/documentation/coreml/mlbatchprovider)

### Accessing values

- [func features(at: Int) -> any MLFeatureProvider](/documentation/coreml/mlbatchprovider/features(at:))
- [var count: Int](/documentation/coreml/mlbatchprovider/count)
- [MLArrayBatchProvider](/documentation/coreml/mlarraybatchprovider)

### Creating a batch provider

- [init(array: [any MLFeatureProvider])](/documentation/coreml/mlarraybatchprovider/init(array:))
- [init(dictionary: [String : [Any]]) throws](/documentation/coreml/mlarraybatchprovider/init(dictionary:))

### Accessing the feature providers

- [var array: [any MLFeatureProvider]](/documentation/coreml/mlarraybatchprovider/array)
- [MLModelAsset](/documentation/coreml/mlmodelasset)

### Creating a model asset

- [convenience init(specification: Data) throws](/documentation/coreml/mlmodelasset/init(specification:))
- [convenience init(specification: Data, blobMapping: [URL : Data]) throws](/documentation/coreml/mlmodelasset/init(specification:blobmapping:))
- [convenience init(url: URL) throws](/documentation/coreml/mlmodelasset/init(url:))

### Getting function names

- [func functionNames(completionHandler: ([String]?, (any Error)?) -> Void)](/documentation/coreml/mlmodelasset/functionnames(completionhandler:))

### Getting the model description

- [func modelDescription(completionHandler: (MLModelDescription?, (any Error)?) -> Void)](/documentation/coreml/mlmodelasset/modeldescription(completionhandler:))
- [func modelDescription(ofFunctionNamed: String, completionHandler: (MLModelDescription?, (any Error)?) -> Void)](/documentation/coreml/mlmodelasset/modeldescription(offunctionnamed:completionhandler:))

## App integration

- [Downloading and Compiling a Model on the User’s Device](/documentation/coreml/downloading-and-compiling-a-model-on-the-user-s-device)
- [Model Integration Samples](/documentation/coreml/model-integration-samples)

### Tabular data models

- [Integrating a Core ML Model into Your App](/documentation/coreml/integrating-a-core-ml-model-into-your-app)

### Image classification models

- [Using Core ML for semantic image segmentation](/documentation/coreml/using-core-ml-for-semantic-image-segmentation)
- [Classifying Images with Vision and Core ML](/documentation/coreml/classifying-images-with-vision-and-core-ml)
- [Detecting human body poses in an image](/documentation/coreml/detecting-human-body-poses-in-an-image)
- [Understanding a Dice Roll with Vision and Object Detection](/documentation/coreml/understanding-a-dice-roll-with-vision-and-object-detection)

### Text classification models

- [Finding answers to questions in a text document](/documentation/coreml/finding-answers-to-questions-in-a-text-document)

## Model encryption

- [Generating a Model Encryption Key](/documentation/coreml/generating-a-model-encryption-key)
- [Encrypting a Model in Your App](/documentation/coreml/encrypting-a-model-in-your-app)

## Compute devices

- [MLComputeDevice](/documentation/coreml/mlcomputedevice)

### Device types

- [case cpu(MLCPUComputeDevice)](/documentation/coreml/mlcomputedevice/cpu(_:))
- [case gpu(MLGPUComputeDevice)](/documentation/coreml/mlcomputedevice/gpu(_:))
- [case neuralEngine(MLNeuralEngineComputeDevice)](/documentation/coreml/mlcomputedevice/neuralengine(_:))

### Getting all devices

- [static var allComputeDevices: [MLComputeDevice]](/documentation/coreml/mlcomputedevice/allcomputedevices)
- [MLCPUComputeDevice](/documentation/coreml/mlcpucomputedevice)
- [MLGPUComputeDevice](/documentation/coreml/mlgpucomputedevice)

### Getting the metal device

- [var metalDevice: (any MTLDevice)!](/documentation/coreml/mlgpucomputedevice/metaldevice)
- [MLNeuralEngineComputeDevice](/documentation/coreml/mlneuralenginecomputedevice)

### Getting the Total Core Count

- [var totalCoreCount: Int](/documentation/coreml/mlneuralenginecomputedevice/totalcorecount)
- [MLComputeDeviceProtocol](/documentation/coreml/mlcomputedeviceprotocol)

## Compute plan

- [MLComputePlan](/documentation/coreml/mlcomputeplan-1w21n)

### Loading a compute plan

- [static func load(asset: MLModelAsset, configuration: MLModelConfiguration) async throws -> MLComputePlan](/documentation/coreml/mlcomputeplan-1w21n/load(asset:configuration:))
- [static func load(contentsOf: URL, configuration: MLModelConfiguration) async throws -> MLComputePlan](/documentation/coreml/mlcomputeplan-1w21n/load(contentsof:configuration:))

### Getting the model structure

- [let modelStructure: MLModelStructure](/documentation/coreml/mlcomputeplan-1w21n/modelstructure)

### Getting the device usage

- [func deviceUsage(for:)](/documentation/coreml/mlcomputeplan-1w21n/deviceusage(for:))
- [func deviceUsage(for: MLModelStructure.NeuralNetwork.Layer) -> MLComputePlan.DeviceUsage?](/documentation/coreml/mlcomputeplan-1w21n/deviceusage(for:)-9em1q)
- [func deviceUsage(for: MLModelStructure.Program.Operation) -> MLComputePlan.DeviceUsage?](/documentation/coreml/mlcomputeplan-1w21n/deviceusage(for:)-7cdlm)
- [MLComputePlan.DeviceUsage](/documentation/coreml/mlcomputeplan-1w21n/deviceusage)

#### Getting the device usage

- [let preferred: MLComputeDevice](/documentation/coreml/mlcomputeplan-1w21n/deviceusage/preferred)
- [let supported: [MLComputeDevice]](/documentation/coreml/mlcomputeplan-1w21n/deviceusage/supported)

### Getting the estimated cost

- [func estimatedCost(of: MLModelStructure.Program.Operation) -> MLComputePlan.Cost?](/documentation/coreml/mlcomputeplan-1w21n/estimatedcost(of:))
- [MLComputePlan.Cost](/documentation/coreml/mlcomputeplan-1w21n/cost)

#### Accessing the weight

- [let weight: Double](/documentation/coreml/mlcomputeplan-1w21n/cost/weight)
- [MLModelStructure](/documentation/coreml/mlmodelstructure-swift.enum)

### Model structures

- [case neuralNetwork(MLModelStructure.NeuralNetwork)](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork(_:))
- [MLModelStructure.NeuralNetwork](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork)

#### Accessing the layers

- [let layers: [MLModelStructure.NeuralNetwork.Layer]](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layers)
- [MLModelStructure.NeuralNetwork.Layer](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer)

##### Accessing layer properties

- [let inputNames: [String]](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer/inputnames)
- [let name: String](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer/name)
- [let outputNames: [String]](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer/outputnames)
- [let type: String](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer/type)
- [case pipeline(MLModelStructure.Pipeline)](/documentation/coreml/mlmodelstructure-swift.enum/pipeline(_:))
- [MLModelStructure.Pipeline](/documentation/coreml/mlmodelstructure-swift.enum/pipeline)

#### Accessing the pipeline model

- [let subModelNames: [String]](/documentation/coreml/mlmodelstructure-swift.enum/pipeline/submodelnames)
- [let subModels: [MLModelStructure]](/documentation/coreml/mlmodelstructure-swift.enum/pipeline/submodels)
- [case program(MLModelStructure.Program)](/documentation/coreml/mlmodelstructure-swift.enum/program(_:))
- [MLModelStructure.Program](/documentation/coreml/mlmodelstructure-swift.enum/program)

#### Accessing the program functions

- [let functions: [String : MLModelStructure.Program.Function]](/documentation/coreml/mlmodelstructure-swift.enum/program/functions)

#### Getting the program types

- [MLModelStructure.Program.Argument](/documentation/coreml/mlmodelstructure-swift.enum/program/argument)

##### Accessing the bindings

- [let bindings: [MLModelStructure.Program.Binding]](/documentation/coreml/mlmodelstructure-swift.enum/program/argument/bindings)
- [MLModelStructure.Program.Block](/documentation/coreml/mlmodelstructure-swift.enum/program/block)

##### Accessing the properties

- [let inputs: [MLModelStructure.Program.NamedValueType]](/documentation/coreml/mlmodelstructure-swift.enum/program/block/inputs)
- [let operations: [MLModelStructure.Program.Operation]](/documentation/coreml/mlmodelstructure-swift.enum/program/block/operations)
- [let outputNames: [String]](/documentation/coreml/mlmodelstructure-swift.enum/program/block/outputnames)
- [MLModelStructure.Program.Function](/documentation/coreml/mlmodelstructure-swift.enum/program/function)

##### Accessing the properties

- [let block: MLModelStructure.Program.Block](/documentation/coreml/mlmodelstructure-swift.enum/program/function/block)
- [let inputs: [MLModelStructure.Program.NamedValueType]](/documentation/coreml/mlmodelstructure-swift.enum/program/function/inputs)
- [MLModelStructure.Program.NamedValueType](/documentation/coreml/mlmodelstructure-swift.enum/program/namedvaluetype)

##### Accessing the properties

- [let name: String](/documentation/coreml/mlmodelstructure-swift.enum/program/namedvaluetype/name)
- [let type: MLModelStructure.Program.ValueType](/documentation/coreml/mlmodelstructure-swift.enum/program/namedvaluetype/type)
- [MLModelStructure.Program.Operation](/documentation/coreml/mlmodelstructure-swift.enum/program/operation)

##### Accessing the properties

- [let blocks: [MLModelStructure.Program.Block]](/documentation/coreml/mlmodelstructure-swift.enum/program/operation/blocks)
- [let inputs: [String : MLModelStructure.Program.Argument]](/documentation/coreml/mlmodelstructure-swift.enum/program/operation/inputs)
- [let operatorName: String](/documentation/coreml/mlmodelstructure-swift.enum/program/operation/operatorname)
- [let outputs: [MLModelStructure.Program.NamedValueType]](/documentation/coreml/mlmodelstructure-swift.enum/program/operation/outputs)
- [MLModelStructure.Program.Value](/documentation/coreml/mlmodelstructure-swift.enum/program/value)
- [MLModelStructure.Program.ValueType](/documentation/coreml/mlmodelstructure-swift.enum/program/valuetype)
- [MLModelStructure.Program.Binding](/documentation/coreml/mlmodelstructure-swift.enum/program/binding)

##### Bindings

- [case name(String)](/documentation/coreml/mlmodelstructure-swift.enum/program/binding/name(_:))
- [case value(MLModelStructure.Program.Value)](/documentation/coreml/mlmodelstructure-swift.enum/program/binding/value(_:))
- [case unsupported](/documentation/coreml/mlmodelstructure-swift.enum/unsupported)

### Loading a model structure

- [static func load(asset: MLModelAsset) async throws -> MLModelStructure](/documentation/coreml/mlmodelstructure-swift.enum/load(asset:))
- [static func load(contentsOf: URL) async throws -> MLModelStructure](/documentation/coreml/mlmodelstructure-swift.enum/load(contentsof:))
- [MLComputePolicy](/documentation/coreml/mlcomputepolicy)

### Compute policies

- [static var cpuAndGPU: MLComputePolicy](/documentation/coreml/mlcomputepolicy/cpuandgpu)
- [static var cpuOnly: MLComputePolicy](/documentation/coreml/mlcomputepolicy/cpuonly)

### Creating a compute policy

- [init(MLComputeUnits)](/documentation/coreml/mlcomputepolicy/init(_:))

### Default Implementations

- [CustomReflectable Implementations](/documentation/coreml/mlcomputepolicy/customreflectable-implementations)

#### Instance Properties

- [var customMirror: Mirror](/documentation/coreml/mlcomputepolicy/custommirror)
- [CustomStringConvertible Implementations](/documentation/coreml/mlcomputepolicy/customstringconvertible-implementations)

#### Instance Properties

- [var description: String](/documentation/coreml/mlcomputepolicy/description)
- [func withMLTensorComputePolicy<R>(MLComputePolicy, () async throws -> R) async rethrows -> R](/documentation/coreml/withmltensorcomputepolicy(_:_:)-8stx9)
- [func withMLTensorComputePolicy<Result>(MLComputePolicy, () throws -> Result) rethrows -> Result](/documentation/coreml/withmltensorcomputepolicy(_:_:)-6z33x)

## Model state

- [MLState](/documentation/coreml/mlstate)

### Getting a state buffer

- [func withMultiArray<R>(for: String, (MLMultiArray) throws -> R) rethrows -> R](/documentation/coreml/mlstate/withmultiarray(for:_:))
- [func withMultiArray<R>((MLMultiArray) -> R) throws -> R](/documentation/coreml/mlstate/withmultiarray(_:))
- [MLStateConstraint](/documentation/coreml/mlstateconstraint)

### Inspecting a state constraint

- [var bufferShape: [Int]](/documentation/coreml/mlstateconstraint/buffershape-4zb3w)
- [var dataType: MLMultiArrayDataType](/documentation/coreml/mlstateconstraint/datatype)

## Model tensor

- [MLTensor](/documentation/coreml/mltensor)

### Creating a tensor

- [init(_:)](/documentation/coreml/mltensor/init(_:))
- [init(some Collection<MLTensor>, alongAxis: Int)](/documentation/coreml/mltensor/init(_:alongaxis:))
- [init(_:scalarType:)](/documentation/coreml/mltensor/init(_:scalartype:))
- [init(bytesNoCopy: UnsafeRawBufferPointer, shape: [Int], scalarType: any MLTensorScalar.Type, deallocator: Data.Deallocator)](/documentation/coreml/mltensor/init(bytesnocopy:shape:scalartype:deallocator:))
- [init(concatenating: some Collection<MLTensor>, alongAxis: Int)](/documentation/coreml/mltensor/init(concatenating:alongaxis:))
- [init(linearSpaceFrom: Float, through: Float, count: Int)](/documentation/coreml/mltensor/init(linearspacefrom:through:count:))
- [init<Scalar>(linearSpaceFrom: Scalar, through: Scalar, count: Int, scalarType: Scalar.Type)](/documentation/coreml/mltensor/init(linearspacefrom:through:count:scalartype:))
- [init(ones:scalarType:)](/documentation/coreml/mltensor/init(ones:scalartype:))
- [init<Scalar>(randomNormal: [Int], mean: Scalar, standardDeviation: Scalar, seed: UInt64?, scalarType: Scalar.Type)](/documentation/coreml/mltensor/init(randomnormal:mean:standarddeviation:seed:scalartype:))
- [init(randomUniform:in:seed:scalarType:)](/documentation/coreml/mltensor/init(randomuniform:in:seed:scalartype:))
- [init(rangeFrom: Float, to: Float, by: Float.Stride)](/documentation/coreml/mltensor/init(rangefrom:to:by:))
- [init<Scalar>(rangeFrom: Scalar, to: Scalar, by: Scalar.Stride, scalarType: Scalar.Type)](/documentation/coreml/mltensor/init(rangefrom:to:by:scalartype:))
- [init(repeating: Float, shape: [Int])](/documentation/coreml/mltensor/init(repeating:shape:))
- [init<Scalar>(repeating: Scalar, shape: [Int], scalarType: Scalar.Type)](/documentation/coreml/mltensor/init(repeating:shape:scalartype:))
- [init(shape: [Int], data: Data, scalarType: any MLTensorScalar.Type)](/documentation/coreml/mltensor/init(shape:data:scalartype:))
- [init(shape: [Int], scalars: some Collection<Float>)](/documentation/coreml/mltensor/init(shape:scalars:))
- [init<Scalar>(shape: [Int], scalars: some Collection, scalarType: Scalar.Type)](/documentation/coreml/mltensor/init(shape:scalars:scalartype:))
- [init(stacking: some Collection<MLTensor>, alongAxis: Int)](/documentation/coreml/mltensor/init(stacking:alongaxis:))
- [init(unsafeUninitializedShape: [Int], scalarType: any MLTensorScalar.Type, initializingWith: (UnsafeMutableRawBufferPointer) throws -> Void) rethrows](/documentation/coreml/mltensor/init(unsafeuninitializedshape:scalartype:initializingwith:))
- [init(zeros:scalarType:)](/documentation/coreml/mltensor/init(zeros:scalartype:))

### Accessing tensor properties

- [var isScalar: Bool](/documentation/coreml/mltensor/isscalar)
- [var rank: Int](/documentation/coreml/mltensor/rank)
- [var scalarCount: Int](/documentation/coreml/mltensor/scalarcount)
- [var scalarType: any MLTensorScalar.Type](/documentation/coreml/mltensor/scalartype)
- [var shape: [Int]](/documentation/coreml/mltensor/shape)

### Getting the sum

- [func sum(alongAxes:keepRank:)](/documentation/coreml/mltensor/sum(alongaxes:keeprank:))
- [func sum(keepRank: Bool) -> MLTensor](/documentation/coreml/mltensor/sum(keeprank:))

### Performing a logical AND operation

- [func all(alongAxes:keepRank:)](/documentation/coreml/mltensor/all(alongaxes:keeprank:))
- [func all(keepRank: Bool) -> MLTensor](/documentation/coreml/mltensor/all(keeprank:))

### Performing a logical OR operation

- [func any(alongAxes:keepRank:)](/documentation/coreml/mltensor/any(alongaxes:keeprank:))
- [func any(keepRank: Bool) -> MLTensor](/documentation/coreml/mltensor/any(keeprank:))

### Accessing the indicies

- [func argmax() -> MLTensor](/documentation/coreml/mltensor/argmax())
- [func argmax(alongAxis: Int, keepRank: Bool) -> MLTensor](/documentation/coreml/mltensor/argmax(alongaxis:keeprank:))
- [func argmin() -> MLTensor](/documentation/coreml/mltensor/argmin())
- [func argmin(alongAxis: Int, keepRank: Bool) -> MLTensor](/documentation/coreml/mltensor/argmin(alongaxis:keeprank:))
- [func argsort(alongAxis: Int, descendingOrder: Bool) -> MLTensor](/documentation/coreml/mltensor/argsort(alongaxis:descendingorder:))

### Casting the elements

- [func cast(like: MLTensor) -> MLTensor](/documentation/coreml/mltensor/cast(like:))
- [func cast<Scalar>(to: Scalar.Type) -> MLTensor](/documentation/coreml/mltensor/cast(to:))

### Computing the absolute, ceiling and floor

- [func abs() -> MLTensor](/documentation/coreml/mltensor/abs())
- [func ceil() -> MLTensor](/documentation/coreml/mltensor/ceil())
- [func floor() -> MLTensor](/documentation/coreml/mltensor/floor())

### Performing arithmetic operations

- [static *(_:_:)](/documentation/coreml/mltensor/*(_:_:))
- [static func *= (inout MLTensor, MLTensor)](/documentation/coreml/mltensor/*=(_:_:))
- [static +(_:_:)](/documentation/coreml/mltensor/+(_:_:))
- [static func += (inout MLTensor, MLTensor)](/documentation/coreml/mltensor/+=(_:_:))
- [static func - (MLTensor) -> MLTensor](/documentation/coreml/mltensor/-(_:))
- [static -(_:_:)](/documentation/coreml/mltensor/-(_:_:))
- [static func -= (inout MLTensor, MLTensor)](/documentation/coreml/mltensor/-=(_:_:))
- [static func .! (MLTensor) -> MLTensor](/documentation/coreml/mltensor/'.!(_:))
- [static .!=(_:_:)](/documentation/coreml/mltensor/'.!=(_:_:))
- [static func .& (MLTensor, MLTensor) -> MLTensor](/documentation/coreml/mltensor/'.&(_:_:))
- [static .==(_:_:)](/documentation/coreml/mltensor/'.==(_:_:))
- [static .>(_:_:)](/documentation/coreml/mltensor/'._(_:_:)-3m3ro)
- [static .<(_:_:)](/documentation/coreml/mltensor/'._(_:_:)-6kfoh)
- [static func .| (MLTensor, MLTensor) -> MLTensor](/documentation/coreml/mltensor/'._(_:_:)-7z7ks)
- [static func .^ (MLTensor, MLTensor) -> MLTensor](/documentation/coreml/mltensor/'._(_:_:)-8il7w)
- [static .>=(_:_:)](/documentation/coreml/mltensor/'._=(_:_:)-5qa2u)
- [static .<=(_:_:)](/documentation/coreml/mltensor/'._=(_:_:)-otif)
- [static /(_:_:)](/documentation/coreml/mltensor/_(_:_:)-5hhe4)
- [static %(_:_:)](/documentation/coreml/mltensor/_(_:_:)-7cfjs)
- [static func %= (inout MLTensor, MLTensor)](/documentation/coreml/mltensor/_=(_:_:)-3xllm)
- [static func /= (inout MLTensor, MLTensor)](/documentation/coreml/mltensor/_=(_:_:)-53k1k)

### Applying trigonometric functions

- [func cos() -> MLTensor](/documentation/coreml/mltensor/cos())
- [func cosh() -> MLTensor](/documentation/coreml/mltensor/cosh())
- [func acos() -> MLTensor](/documentation/coreml/mltensor/acos())
- [func acosh() -> MLTensor](/documentation/coreml/mltensor/acosh())
- [func sin() -> MLTensor](/documentation/coreml/mltensor/sin())
- [func sinh() -> MLTensor](/documentation/coreml/mltensor/sinh())
- [func asin() -> MLTensor](/documentation/coreml/mltensor/asin())
- [func asinh() -> MLTensor](/documentation/coreml/mltensor/asinh())
- [func tan() -> MLTensor](/documentation/coreml/mltensor/tan())
- [func tanh() -> MLTensor](/documentation/coreml/mltensor/tanh())
- [func atan() -> MLTensor](/documentation/coreml/mltensor/atan())
- [func atanh() -> MLTensor](/documentation/coreml/mltensor/atanh())

### Accessing the minimum, maximum and mean

- [func min(alongAxes:keepRank:)](/documentation/coreml/mltensor/min(alongaxes:keeprank:))
- [func min(keepRank: Bool) -> MLTensor](/documentation/coreml/mltensor/min(keeprank:))
- [func max(alongAxes:keepRank:)](/documentation/coreml/mltensor/max(alongaxes:keeprank:))
- [func max(keepRank: Bool) -> MLTensor](/documentation/coreml/mltensor/max(keeprank:))
- [func mean(alongAxes:keepRank:)](/documentation/coreml/mltensor/mean(alongaxes:keeprank:))
- [func mean(keepRank: Bool) -> MLTensor](/documentation/coreml/mltensor/mean(keeprank:))

### Splitting the tensor

- [func split(count: Int, alongAxis: Int) -> [MLTensor]](/documentation/coreml/mltensor/split(count:alongaxis:))
- [func split(sizes: [Int], alongAxis: Int) -> [MLTensor]](/documentation/coreml/mltensor/split(sizes:alongaxis:))

### Resizing the tensor

- [func resized(to: (newHeight: Int, newWidth: Int), method: MLTensor.ResizeMethod) -> MLTensor](/documentation/coreml/mltensor/resized(to:method:))
- [MLTensor.ResizeMethod](/documentation/coreml/mltensor/resizemethod)

#### Resize methods

- [case bilinear(alignCorners: Bool)](/documentation/coreml/mltensor/resizemethod/bilinear(aligncorners:))
- [case nearestNeighbor](/documentation/coreml/mltensor/resizemethod/nearestneighbor)

### Padding the tensor

- [func padded(forSizes: [(before: Int, after: Int)], mode: MLTensor.PaddingMode) -> MLTensor](/documentation/coreml/mltensor/padded(forsizes:mode:))
- [func padded(forSizes: [(before: Int, after: Int)], with: Float) -> MLTensor](/documentation/coreml/mltensor/padded(forsizes:with:))
- [MLTensor.PaddingMode](/documentation/coreml/mltensor/paddingmode)

#### Padding modes

- [case constant(Float)](/documentation/coreml/mltensor/paddingmode/constant(_:))
- [case reflection](/documentation/coreml/mltensor/paddingmode/reflection)
- [case symmetric](/documentation/coreml/mltensor/paddingmode/symmetric)

### Replacing the tensor values

- [func replacing(atIndices: MLTensor, with: some MLTensorScalar, alongAxis: Int) -> MLTensor](/documentation/coreml/mltensor/replacing(atindices:with:alongaxis:))
- [func replacing(with: MLTensor, atIndices: MLTensor, alongAxis: Int) -> MLTensor](/documentation/coreml/mltensor/replacing(with:atindices:alongaxis:))
- [func replacing(with:where:)](/documentation/coreml/mltensor/replacing(with:where:))

### Gathering slices

- [func gathering(atIndices: MLTensor) -> MLTensor](/documentation/coreml/mltensor/gathering(atindices:))
- [func gathering(atIndices: MLTensor, alongAxis: Int) -> MLTensor](/documentation/coreml/mltensor/gathering(atindices:alongaxis:))

### Transposing the tensor

- [func transposed() -> MLTensor](/documentation/coreml/mltensor/transposed())
- [func transposed(permutation:)](/documentation/coreml/mltensor/transposed(permutation:))

### Unpacking the tensor

- [func unstacked(alongAxis: Int) -> [MLTensor]](/documentation/coreml/mltensor/unstacked(alongaxis:))

### Getting the shaped representation of the tensor

- [func shapedArray<Scalar>(of: Scalar.Type) async -> MLShapedArray<Scalar>](/documentation/coreml/mltensor/shapedarray(of:))

### Removing dimensions from the shape of the tensor

- [func squeezingShape() -> MLTensor](/documentation/coreml/mltensor/squeezingshape())
- [func squeezingShape(at:)](/documentation/coreml/mltensor/squeezingshape(at:))

### Accessing the product along an axes

- [func product(alongAxes:keepRank:)](/documentation/coreml/mltensor/product(alongaxes:keeprank:))
- [func product(keepRank: Bool) -> MLTensor](/documentation/coreml/mltensor/product(keeprank:))

### Getting the largest values

- [func topK(Int) -> (values: MLTensor, indices: MLTensor)](/documentation/coreml/mltensor/topk(_:))

### Clamping and concatenating

- [func clamped(to:)](/documentation/coreml/mltensor/clamped(to:))
- [func concatenated(with: MLTensor, alongAxis: Int) -> MLTensor](/documentation/coreml/mltensor/concatenated(with:alongaxis:))

### Computing the cumulative value

- [func cumulativeProduct(alongAxis: Int) -> MLTensor](/documentation/coreml/mltensor/cumulativeproduct(alongaxis:))
- [func cumulativeSum(alongAxis: Int) -> MLTensor](/documentation/coreml/mltensor/cumulativesum(alongaxis:))

### Computing the exponent, pow and square root

- [func exp() -> MLTensor](/documentation/coreml/mltensor/exp())
- [func exp2() -> MLTensor](/documentation/coreml/mltensor/exp2())
- [func pow(_:)](/documentation/coreml/mltensor/pow(_:))
- [func rsqrt() -> MLTensor](/documentation/coreml/mltensor/rsqrt())
- [func squared() -> MLTensor](/documentation/coreml/mltensor/squared())
- [func squareRoot() -> MLTensor](/documentation/coreml/mltensor/squareroot())
- [func log() -> MLTensor](/documentation/coreml/mltensor/log())
- [func round() -> MLTensor](/documentation/coreml/mltensor/round())
- [func matmul(MLTensor) -> MLTensor](/documentation/coreml/mltensor/matmul(_:))

### Accessing the extended tensor, sign and reciprocal

- [func expandingShape(at:)](/documentation/coreml/mltensor/expandingshape(at:))
- [func bandPart(lowerBandCount: Int, upperBandCount: Int) -> MLTensor](/documentation/coreml/mltensor/bandpart(lowerbandcount:upperbandcount:))
- [func tiled(multiples: [Int]) -> MLTensor](/documentation/coreml/mltensor/tiled(multiples:))
- [func sign() -> MLTensor](/documentation/coreml/mltensor/sign())
- [func reciprocal() -> MLTensor](/documentation/coreml/mltensor/reciprocal())

### Reshaping the tensor

- [func flattened() -> MLTensor](/documentation/coreml/mltensor/flattened())
- [func reshaped(to: [Int]) -> MLTensor](/documentation/coreml/mltensor/reshaped(to:))

### Computing the softmax

- [func softmax(alongAxis: Int) -> MLTensor](/documentation/coreml/mltensor/softmax(alongaxis:))

### Reversing the tensor

- [func reversed(alongAxes:)](/documentation/coreml/mltensor/reversed(alongaxes:))

### Accessing a multiarray’s elements

- [subscript((any MLTensorRangeExpression)?...) -> MLTensor](/documentation/coreml/mltensor/subscript(_:))
- [subscript((UnboundedRange_) -> (), (any MLTensorRangeExpression)?...) -> MLTensor](/documentation/coreml/mltensor/subscript(_:_:))
- [subscript((any MLTensorRangeExpression)?, (UnboundedRange_) -> (), (any MLTensorRangeExpression)?...) -> MLTensor](/documentation/coreml/mltensor/subscript(_:_:_:))
- [subscript((any MLTensorRangeExpression)?, (any MLTensorRangeExpression)?, (UnboundedRange_) -> (), (any MLTensorRangeExpression)?...) -> MLTensor](/documentation/coreml/mltensor/subscript(_:_:_:_:))
- [subscript((any MLTensorRangeExpression)?, (any MLTensorRangeExpression)?, (any MLTensorRangeExpression)?, (UnboundedRange_) -> (), (any MLTensorRangeExpression)?...) -> MLTensor](/documentation/coreml/mltensor/subscript(_:_:_:_:_:))

### Default Implementations

- [CustomReflectable Implementations](/documentation/coreml/mltensor/customreflectable-implementations)

#### Instance Properties

- [var customMirror: Mirror](/documentation/coreml/mltensor/custommirror)
- [MLTensorScalar](/documentation/coreml/mltensorscalar)
- [MLTensorRangeExpression](/documentation/coreml/mltensorrangeexpression)

### Expanding and squeezing the tensor

- [static var newAxis: any MLTensorRangeExpression](/documentation/coreml/mltensorrangeexpression/newaxis)
- [static var squeezeAxis: any MLTensorRangeExpression](/documentation/coreml/mltensorrangeexpression/squeezeaxis)
- [static var fillAll: any MLTensorRangeExpression](/documentation/coreml/mltensorrangeexpression/fillall)

### Slicing the tensor

- [static func closedRange(ClosedRange<Int>, stride: Int) -> any MLTensorRangeExpression](/documentation/coreml/mltensorrangeexpression/closedrange(_:stride:))
- [static func index(Int) -> any MLTensorRangeExpression](/documentation/coreml/mltensorrangeexpression/index(_:))
- [static func partialRangeFrom(PartialRangeFrom<Int>, stride: Int) -> any MLTensorRangeExpression](/documentation/coreml/mltensorrangeexpression/partialrangefrom(_:stride:))
- [static partialRangeUpTo(_:stride:)](/documentation/coreml/mltensorrangeexpression/partialrangeupto(_:stride:))
- [static func range(Range<Int>, stride: Int) -> any MLTensorRangeExpression](/documentation/coreml/mltensorrangeexpression/range(_:stride:))
- [func pointwiseMin(_:_:)](/documentation/coreml/pointwisemin(_:_:))
- [func pointwiseMax(_:_:)](/documentation/coreml/pointwisemax(_:_:))
- [func withMLTensorComputePolicy(_:_:)](/documentation/coreml/withmltensorcomputepolicy(_:_:))

## Model structure

- [MLModelStructure](/documentation/coreml/mlmodelstructure-swift.enum)

### Model structures

- [case neuralNetwork(MLModelStructure.NeuralNetwork)](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork(_:))
- [MLModelStructure.NeuralNetwork](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork)

#### Accessing the layers

- [let layers: [MLModelStructure.NeuralNetwork.Layer]](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layers)
- [MLModelStructure.NeuralNetwork.Layer](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer)

##### Accessing layer properties

- [let inputNames: [String]](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer/inputnames)
- [let name: String](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer/name)
- [let outputNames: [String]](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer/outputnames)
- [let type: String](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer/type)
- [case pipeline(MLModelStructure.Pipeline)](/documentation/coreml/mlmodelstructure-swift.enum/pipeline(_:))
- [MLModelStructure.Pipeline](/documentation/coreml/mlmodelstructure-swift.enum/pipeline)

#### Accessing the pipeline model

- [let subModelNames: [String]](/documentation/coreml/mlmodelstructure-swift.enum/pipeline/submodelnames)
- [let subModels: [MLModelStructure]](/documentation/coreml/mlmodelstructure-swift.enum/pipeline/submodels)
- [case program(MLModelStructure.Program)](/documentation/coreml/mlmodelstructure-swift.enum/program(_:))
- [MLModelStructure.Program](/documentation/coreml/mlmodelstructure-swift.enum/program)

#### Accessing the program functions

- [let functions: [String : MLModelStructure.Program.Function]](/documentation/coreml/mlmodelstructure-swift.enum/program/functions)

#### Getting the program types

- [MLModelStructure.Program.Argument](/documentation/coreml/mlmodelstructure-swift.enum/program/argument)

##### Accessing the bindings

- [let bindings: [MLModelStructure.Program.Binding]](/documentation/coreml/mlmodelstructure-swift.enum/program/argument/bindings)
- [MLModelStructure.Program.Block](/documentation/coreml/mlmodelstructure-swift.enum/program/block)

##### Accessing the properties

- [let inputs: [MLModelStructure.Program.NamedValueType]](/documentation/coreml/mlmodelstructure-swift.enum/program/block/inputs)
- [let operations: [MLModelStructure.Program.Operation]](/documentation/coreml/mlmodelstructure-swift.enum/program/block/operations)
- [let outputNames: [String]](/documentation/coreml/mlmodelstructure-swift.enum/program/block/outputnames)
- [MLModelStructure.Program.Function](/documentation/coreml/mlmodelstructure-swift.enum/program/function)

##### Accessing the properties

- [let block: MLModelStructure.Program.Block](/documentation/coreml/mlmodelstructure-swift.enum/program/function/block)
- [let inputs: [MLModelStructure.Program.NamedValueType]](/documentation/coreml/mlmodelstructure-swift.enum/program/function/inputs)
- [MLModelStructure.Program.NamedValueType](/documentation/coreml/mlmodelstructure-swift.enum/program/namedvaluetype)

##### Accessing the properties

- [let name: String](/documentation/coreml/mlmodelstructure-swift.enum/program/namedvaluetype/name)
- [let type: MLModelStructure.Program.ValueType](/documentation/coreml/mlmodelstructure-swift.enum/program/namedvaluetype/type)
- [MLModelStructure.Program.Operation](/documentation/coreml/mlmodelstructure-swift.enum/program/operation)

##### Accessing the properties

- [let blocks: [MLModelStructure.Program.Block]](/documentation/coreml/mlmodelstructure-swift.enum/program/operation/blocks)
- [let inputs: [String : MLModelStructure.Program.Argument]](/documentation/coreml/mlmodelstructure-swift.enum/program/operation/inputs)
- [let operatorName: String](/documentation/coreml/mlmodelstructure-swift.enum/program/operation/operatorname)
- [let outputs: [MLModelStructure.Program.NamedValueType]](/documentation/coreml/mlmodelstructure-swift.enum/program/operation/outputs)
- [MLModelStructure.Program.Value](/documentation/coreml/mlmodelstructure-swift.enum/program/value)
- [MLModelStructure.Program.ValueType](/documentation/coreml/mlmodelstructure-swift.enum/program/valuetype)
- [MLModelStructure.Program.Binding](/documentation/coreml/mlmodelstructure-swift.enum/program/binding)

##### Bindings

- [case name(String)](/documentation/coreml/mlmodelstructure-swift.enum/program/binding/name(_:))
- [case value(MLModelStructure.Program.Value)](/documentation/coreml/mlmodelstructure-swift.enum/program/binding/value(_:))
- [case unsupported](/documentation/coreml/mlmodelstructure-swift.enum/unsupported)

### Loading a model structure

- [static func load(asset: MLModelAsset) async throws -> MLModelStructure](/documentation/coreml/mlmodelstructure-swift.enum/load(asset:))
- [static func load(contentsOf: URL) async throws -> MLModelStructure](/documentation/coreml/mlmodelstructure-swift.enum/load(contentsof:))

## Model errors

- [MLModelError](/documentation/coreml/mlmodelerror-swift.struct)

### Error Codes

- [static var featureType: MLModelError.Code](/documentation/coreml/mlmodelerror-swift.struct/featuretype)
- [static var parameters: MLModelError.Code](/documentation/coreml/mlmodelerror-swift.struct/parameters)
- [static var modelCollection: MLModelError.Code](/documentation/coreml/mlmodelerror-swift.struct/modelcollection)
- [static var modelDecryptionKeyFetch: MLModelError.Code](/documentation/coreml/mlmodelerror-swift.struct/modeldecryptionkeyfetch)
- [static var modelDecryption: MLModelError.Code](/documentation/coreml/mlmodelerror-swift.struct/modeldecryption)
- [static var update: MLModelError.Code](/documentation/coreml/mlmodelerror-swift.struct/update)
- [static var customLayer: MLModelError.Code](/documentation/coreml/mlmodelerror-swift.struct/customlayer)
- [static var customModel: MLModelError.Code](/documentation/coreml/mlmodelerror-swift.struct/custommodel)
- [static var io: MLModelError.Code](/documentation/coreml/mlmodelerror-swift.struct/io)
- [static var predictionCancelled: MLModelError.Code](/documentation/coreml/mlmodelerror-swift.struct/predictioncancelled)
- [static var generic: MLModelError.Code](/documentation/coreml/mlmodelerror-swift.struct/generic)
- [MLModelError.Code](/documentation/coreml/mlmodelerror-swift.struct/code)

#### Error codes

- [case featureType](/documentation/coreml/mlmodelerror-swift.struct/code/featuretype)
- [case parameters](/documentation/coreml/mlmodelerror-swift.struct/code/parameters)
- [case modelCollection](/documentation/coreml/mlmodelerror-swift.struct/code/modelcollection)
- [case modelDecryptionKeyFetch](/documentation/coreml/mlmodelerror-swift.struct/code/modeldecryptionkeyfetch)
- [case modelDecryption](/documentation/coreml/mlmodelerror-swift.struct/code/modeldecryption)
- [case update](/documentation/coreml/mlmodelerror-swift.struct/code/update)
- [case customLayer](/documentation/coreml/mlmodelerror-swift.struct/code/customlayer)
- [case customModel](/documentation/coreml/mlmodelerror-swift.struct/code/custommodel)
- [case io](/documentation/coreml/mlmodelerror-swift.struct/code/io)
- [case predictionCancelled](/documentation/coreml/mlmodelerror-swift.struct/code/predictioncancelled)
- [case generic](/documentation/coreml/mlmodelerror-swift.struct/code/generic)

#### Error domain

- [let MLModelErrorDomain: String](/documentation/coreml/mlmodelerrordomain)
- [static var errorDomain: String](/documentation/coreml/mlmodelerror-swift.struct/errordomain)

#### Creating a model error

- [init?(rawValue: Int)](/documentation/coreml/mlmodelerror-swift.struct/code/init(rawvalue:))

### Error Domain

- [let MLModelErrorDomain: String](/documentation/coreml/mlmodelerrordomain)
- [static var errorDomain: String](/documentation/coreml/mlmodelerror-swift.struct/errordomain)
- [MLModelError.Code](/documentation/coreml/mlmodelerror-swift.struct/code)

### Error codes

- [case featureType](/documentation/coreml/mlmodelerror-swift.struct/code/featuretype)
- [case parameters](/documentation/coreml/mlmodelerror-swift.struct/code/parameters)
- [case modelCollection](/documentation/coreml/mlmodelerror-swift.struct/code/modelcollection)
- [case modelDecryptionKeyFetch](/documentation/coreml/mlmodelerror-swift.struct/code/modeldecryptionkeyfetch)
- [case modelDecryption](/documentation/coreml/mlmodelerror-swift.struct/code/modeldecryption)
- [case update](/documentation/coreml/mlmodelerror-swift.struct/code/update)
- [case customLayer](/documentation/coreml/mlmodelerror-swift.struct/code/customlayer)
- [case customModel](/documentation/coreml/mlmodelerror-swift.struct/code/custommodel)
- [case io](/documentation/coreml/mlmodelerror-swift.struct/code/io)
- [case predictionCancelled](/documentation/coreml/mlmodelerror-swift.struct/code/predictioncancelled)
- [case generic](/documentation/coreml/mlmodelerror-swift.struct/code/generic)

### Error domain

- [let MLModelErrorDomain: String](/documentation/coreml/mlmodelerrordomain)
- [static var errorDomain: String](/documentation/coreml/mlmodelerror-swift.struct/errordomain)

### Creating a model error

- [init?(rawValue: Int)](/documentation/coreml/mlmodelerror-swift.struct/code/init(rawvalue:))
- [let MLModelErrorDomain: String](/documentation/coreml/mlmodelerrordomain)

## Model deployments

- [MLModelCollection](/documentation/coreml/mlmodelcollection)

### Accessing a model collection

- [class func endAccessing(identifier: String) async throws -> Bool](/documentation/coreml/mlmodelcollection/endaccessing(identifier:))

### Identifying a model collection

- [var identifier: String](/documentation/coreml/mlmodelcollection/identifier)
- [var deploymentID: String](/documentation/coreml/mlmodelcollection/deploymentid)

### Retreiving models from a collection

- [var entries: [String : MLModelCollection.Entry]](/documentation/coreml/mlmodelcollection/entries)
- [MLModelCollection.Entry](/documentation/coreml/mlmodelcollection/entry)

#### Identifying a model

- [var modelIdentifier: String](/documentation/coreml/mlmodelcollection/entry/modelidentifier)

#### Locating a compiled model file

- [var modelURL: URL](/documentation/coreml/mlmodelcollection/entry/modelurl)

#### Comparing model collection entries

- [func isEqual(to: MLModelCollection.Entry) -> Bool](/documentation/coreml/mlmodelcollection/entry/isequal(to:))

### Registering for model collection updates

- [class let didChangeNotification: NSNotification.Name](/documentation/coreml/mlmodelcollection/didchangenotification)

## Reference

- [CoreML Enumerations](/documentation/coreml/coreml-enumerations)

### Enumerations

- [MLModelStructure](/documentation/coreml/mlmodelstructure-swift.enum)

#### Model structures

- [case neuralNetwork(MLModelStructure.NeuralNetwork)](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork(_:))
- [MLModelStructure.NeuralNetwork](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork)

##### Accessing the layers

- [let layers: [MLModelStructure.NeuralNetwork.Layer]](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layers)
- [MLModelStructure.NeuralNetwork.Layer](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer)

###### Accessing layer properties

- [let inputNames: [String]](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer/inputnames)
- [let name: String](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer/name)
- [let outputNames: [String]](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer/outputnames)
- [let type: String](/documentation/coreml/mlmodelstructure-swift.enum/neuralnetwork/layer/type)
- [case pipeline(MLModelStructure.Pipeline)](/documentation/coreml/mlmodelstructure-swift.enum/pipeline(_:))
- [MLModelStructure.Pipeline](/documentation/coreml/mlmodelstructure-swift.enum/pipeline)

##### Accessing the pipeline model

- [let subModelNames: [String]](/documentation/coreml/mlmodelstructure-swift.enum/pipeline/submodelnames)
- [let subModels: [MLModelStructure]](/documentation/coreml/mlmodelstructure-swift.enum/pipeline/submodels)
- [case program(MLModelStructure.Program)](/documentation/coreml/mlmodelstructure-swift.enum/program(_:))
- [MLModelStructure.Program](/documentation/coreml/mlmodelstructure-swift.enum/program)

##### Accessing the program functions

- [let functions: [String : MLModelStructure.Program.Function]](/documentation/coreml/mlmodelstructure-swift.enum/program/functions)

##### Getting the program types

- [MLModelStructure.Program.Argument](/documentation/coreml/mlmodelstructure-swift.enum/program/argument)

###### Accessing the bindings

- [let bindings: [MLModelStructure.Program.Binding]](/documentation/coreml/mlmodelstructure-swift.enum/program/argument/bindings)
- [MLModelStructure.Program.Block](/documentation/coreml/mlmodelstructure-swift.enum/program/block)

###### Accessing the properties

- [let inputs: [MLModelStructure.Program.NamedValueType]](/documentation/coreml/mlmodelstructure-swift.enum/program/block/inputs)
- [let operations: [MLModelStructure.Program.Operation]](/documentation/coreml/mlmodelstructure-swift.enum/program/block/operations)
- [let outputNames: [String]](/documentation/coreml/mlmodelstructure-swift.enum/program/block/outputnames)
- [MLModelStructure.Program.Function](/documentation/coreml/mlmodelstructure-swift.enum/program/function)

###### Accessing the properties

- [let block: MLModelStructure.Program.Block](/documentation/coreml/mlmodelstructure-swift.enum/program/function/block)
- [let inputs: [MLModelStructure.Program.NamedValueType]](/documentation/coreml/mlmodelstructure-swift.enum/program/function/inputs)
- [MLModelStructure.Program.NamedValueType](/documentation/coreml/mlmodelstructure-swift.enum/program/namedvaluetype)

###### Accessing the properties

- [let name: String](/documentation/coreml/mlmodelstructure-swift.enum/program/namedvaluetype/name)
- [let type: MLModelStructure.Program.ValueType](/documentation/coreml/mlmodelstructure-swift.enum/program/namedvaluetype/type)
- [MLModelStructure.Program.Operation](/documentation/coreml/mlmodelstructure-swift.enum/program/operation)

###### Accessing the properties

- [let blocks: [MLModelStructure.Program.Block]](/documentation/coreml/mlmodelstructure-swift.enum/program/operation/blocks)
- [let inputs: [String : MLModelStructure.Program.Argument]](/documentation/coreml/mlmodelstructure-swift.enum/program/operation/inputs)
- [let operatorName: String](/documentation/coreml/mlmodelstructure-swift.enum/program/operation/operatorname)
- [let outputs: [MLModelStructure.Program.NamedValueType]](/documentation/coreml/mlmodelstructure-swift.enum/program/operation/outputs)
- [MLModelStructure.Program.Value](/documentation/coreml/mlmodelstructure-swift.enum/program/value)
- [MLModelStructure.Program.ValueType](/documentation/coreml/mlmodelstructure-swift.enum/program/valuetype)
- [MLModelStructure.Program.Binding](/documentation/coreml/mlmodelstructure-swift.enum/program/binding)

###### Bindings

- [case name(String)](/documentation/coreml/mlmodelstructure-swift.enum/program/binding/name(_:))
- [case value(MLModelStructure.Program.Value)](/documentation/coreml/mlmodelstructure-swift.enum/program/binding/value(_:))
- [case unsupported](/documentation/coreml/mlmodelstructure-swift.enum/unsupported)

#### Loading a model structure

- [static func load(asset: MLModelAsset) async throws -> MLModelStructure](/documentation/coreml/mlmodelstructure-swift.enum/load(asset:))
- [static func load(contentsOf: URL) async throws -> MLModelStructure](/documentation/coreml/mlmodelstructure-swift.enum/load(contentsof:))
- [MLShapedArrayBufferLayout](/documentation/coreml/mlshapedarraybufferlayout)

#### Buffer layouts

- [case firstMajorContiguous](/documentation/coreml/mlshapedarraybufferlayout/firstmajorcontiguous)
- [case lastMajorContiguous](/documentation/coreml/mlshapedarraybufferlayout/lastmajorcontiguous)
- [case strides([Int])](/documentation/coreml/mlshapedarraybufferlayout/strides(_:))

---

*Extracted by [sosumi.ai](https://sosumi.ai) - Making Apple docs AI-readable.*
*This is unofficial content. All documentation belongs to Apple Inc.*