# Adding intelligent app features with generative models

Build robust apps with guided generation and tool calling by adopting the Foundation Models framework.

Download:
[https://docs-assets.developer.apple.com/published/5414fd17db13/AddingIntelligentAppFeaturesWithGenerativeModels.zip](https://docs-assets.developer.apple.com/published/5414fd17db13/AddingIntelligentAppFeaturesWithGenerativeModels.zip)

Availability: iOS 26.0+, iPadOS 26.0+, macOS 26.0+, visionOS 26.0+
Xcode: 26.0+

## Overview

This sample project shows how to integrate generative AI capabilities into an app using the Foundation Models framework. The sample app showcases intelligent trip planning features that help people discover landmarks and generate personalized itineraries.

The app creates an interactive experience where people can:

* Browse curated landmarks with rich visual content
* Generate trip itineraries tailored to a chosen landmark
* Discover points of interest using a custom tool
* Experience real-time content generation with streaming responses

Note: This sample code project is associated with WWDC25 session 259:
[https://developer.apple.com/wwdc25/259/](https://developer.apple.com/wwdc25/259/)

## Configure the sample code project

To run this sample, you’ll need to:

1. Set the developer team in Xcode for the app target so it automatically manages the provisioning profile.
   References:

   * Set the bundle ID: [https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution#Set-the-bundle-ID](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution#Set-the-bundle-ID)
   * Assign the project to a team: [https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution#Assign-the-project-to-a-team](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution#Assign-the-project-to-a-team)

2. In the Developer portal, enable the WeatherKit app service for your bundle ID so the app can access location-based weather information.

## Check model availability

Before using the on-device model in the app, check that the model is available by creating an instance of `SystemLanguageModel` with the `default` property:

```swift
let landmark: Landmark
private let model = SystemLanguageModel.default

var body: some View {
    switch model.availability {
    case .available:
        LandmarkTripView(landmark: landmark)

    case .unavailable(.appleIntelligenceNotEnabled):
        MessageView(
            landmark: self.landmark,
            message: """
            Trip Planner is unavailable because \
            Apple Intelligence hasn't been turned on.
            """
        )

    case .unavailable(.modelNotReady):
        MessageView(
            landmark: self.landmark,
            message: "Trip Planner isn't ready yet. Try again later."
        )
    }
}
```

The app handles two unavailability scenarios: Apple Intelligence isn’t enabled or the model isn’t ready for usage. If Apple Intelligence is off, the app tells the person they need to turn it on. If the model isn’t ready, it tells the person the Trip Planner isn’t ready and to try the app again later.

Note: To use the on-device language model, people need to turn on Apple Intelligence on their device. For a list of supported devices, see:
[https://www.apple.com/apple-intelligence/](https://www.apple.com/apple-intelligence/)

## Define structured data for generation

The app starts by defining data structures with specific constraints to control what the model generates. The `Itinerary` type uses the `Generable` macro to create structured content that includes travel plans with activities, hotels, and restaurants.

The `@Generable` macro automatically converts Swift types into schemas that the model uses for constrained sampling, so you can specify guides to control the values you associate with it.

For example, the app uses `Guide(description:)` to make sure the model creates an exciting name for the trip. It also uses `anyOf(_:)` and `count(_:)` to choose a destination from `ModelData` and show exactly 3 `DayPlan` objects per destination, respectively.

```swift
@Generable
struct Itinerary: Equatable {
    @Guide(description: "An exciting name for the trip.")
    let title: String

    @Guide(.anyOf(ModelData.landmarkNames))
    let destinationName: String

    let description: String

    @Guide(description: "An explanation of how the itinerary meets the person's special requests.")
    let rationale: String

    @Guide(description: "A list of day-by-day plans.")
    @Guide(.count(3))
    let days: [DayPlan]
}

@Generable
struct DayPlan: Equatable {
    @Guide(description: "A unique and exciting title for this day plan.")
    let title: String

    let subtitle: String
    let destination: String

    @Guide(.count(3))
    let activities: [Activity]
}

@Generable
struct Activity: Equatable {
    let type: Kind
    let title: String
    let description: String
}

@Generable
enum Kind {
    case sightseeing
    case foodAndDining
    case shopping
    case hotelAndLodging
}
```

The `@Generable` macro automatically creates two versions of each type: the complete structure and a `PartiallyGenerated` version which mirrors the outer structure, except every property is optional. The app uses this `PartiallyGenerated` version when streaming and displaying the itinerary generation.

Reference:
[https://developer.apple.com/documentation/foundationmodels/generable/partiallygenerated](https://developer.apple.com/documentation/foundationmodels/generable/partiallygenerated)

## Configure the model session

After checking that the model is available, the app configures a `LanguageModelSession` object with custom tools and detailed instructions in `ItineraryPlanner`.

Given a location, the initializer creates the session with structured guidance for generating personalized trip recommendations:

```swift
init(landmark: Landmark) {
    self.landmark = landmark
    Logging.general.log("The landmark is... \(landmark.name)")

    let pointOfInterestTool = FindPointsOfInterestTool(landmark: landmark)

    self.session = LanguageModelSession(
        tools: [pointOfInterestTool],
        instructions: Instructions {
            "Your job is to create an itinerary for the person."
            "Each day needs an activity, hotel and restaurant."
            """
            Always use the findPointsOfInterest tool to find businesses \
            and activities in \(landmark.name), especially hotels \
            and restaurants. The point of interest categories may include:
            """
            FindPointsOfInterestTool.categories
            """
            Here is a description of \(landmark.name) for your reference \
            when considering what activities to generate:
            """
            landmark.description
        }
    )

    self.pointOfInterestTool = pointOfInterestTool
}
```

In a generated itinerary, the model instructions ensure that each day contains an activity, hotel, and restaurant. To get the location-specific businesses and activities, the sample uses a custom tool called `FindPointsOfInterestTool`, scoped to the chosen landmark. The instructions also include the landmark description as additional context when generating activities.

## Create a custom tool

You can use custom tools to extend the functionality of a model. Tool-calling allows the model to interact with external code you create to fetch up-to-date information, ground responses in sources of truth, and perform side effects.

The model in this app uses `FindPointsOfInterestTool` to enable dynamic discovery of specific businesses and activities for the chosen landmark. The tool uses `@Generable` to make its categories and arguments available to the model.

```swift
@Observable
final class FindPointsOfInterestTool: Tool {
    let name = "findPointsOfInterest"
    let description = "Finds points of interest for a landmark."
    let landmark: Landmark

    @MainActor
    var lookupHistory: [Lookup] = []

    init(landmark: Landmark) {
        self.landmark = landmark
    }

    @Generable
    enum Category: String, CaseIterable {
        case campground
        case hotel
        case cafe
        case museum
        case marina
        case restaurant
        case nationalMonument
    }

    @Generable
    struct Arguments {
        @Guide(description: "This is the type of destination to look up for.")
        let pointOfInterest: Category

        @Guide(description: "The natural language query of what to search for.")
        let naturalLanguageQuery: String
    }
}
```

When you prompt the model, it decides whether it can answer directly or whether it needs help from a tool. The app explicitly instructs the model to always use `findPointsOfInterest` in `ItineraryPlanner`, enabling the model to call the tool for hotels, restaurants, and activities.

## Stream and display partial responses in real time

The app shows real-time content generation by streaming partial responses from the model.

`ItineraryPlanner` uses `streamResponse(generating:includeSchemaInPrompt:options:prompt:)` to generate `Itinerary.PartiallyGenerated` objects, so itinerary items are shown incrementally.

For generating the itinerary, the app opts for a greedy sampling mode so the model produces consistent output for a given input. This yields stable recommendations for a landmark-specific itinerary.

```swift
private(set) var itinerary: Itinerary.PartiallyGenerated?

func suggestItinerary(dayCount: Int) async throws {
    let stream = session.streamResponse(
        generating: Itinerary.self,
        includeSchemaInPrompt: false,
        options: GenerationOptions(sampling: .greedy)
    ) {
        "Generate a \(dayCount)-day itinerary to \(landmark.name)."
        "Give it a fun title and description."
        "Here is an example, but don't copy it:"
        Itinerary.exampleTripToJapan
    }

    for try await partialResponse in stream {
        itinerary = partialResponse.content
    }
}
```

The app presents these responses in SwiftUI. `ItineraryPlanningView` displays real-time feedback as the model searches for points of interest:

```swift
ForEach(planner.pointOfInterestTool.lookupHistory) { element in
    HStack {
        Image(systemName: "location.magnifyingglass")
        Text("Searching **\(element.history.pointOfInterest.rawValue)** in \(landmark.name)...")
    }
    .transition(.blurReplace)
}
```

The view shows status messages such as “Searching hotel in Yosemite…” to make the process legible to the person using the app, while the tool runs in the background and updates the view as results arrive.

## Tag content dynamically

The app uses content tagging on the provided landmarks to help people quickly understand the characteristics of each destination.

A content tagging model produces a list of categorizing tags based on the input text you provide. When prompted, it produces a tag that uses one to a few lowercase words.

`LandmarkDescriptionView` prompts the content tagging model to automatically generate relevant hashtags for landmark descriptions, like `#nature`, `#hiking`, or `#scenic`, based on each landmark’s description.

For more information on initializing content tagging, see:
[https://developer.apple.com/documentation/FoundationModels/categorizing-and-organizing-data-with-content-tags](https://developer.apple.com/documentation/FoundationModels/categorizing-and-organizing-data-with-content-tags)

```swift
let contentTaggingModel = SystemLanguageModel(useCase: .contentTagging)

.task {
    if !contentTaggingModel.isAvailable { return }

    do {
        let session = LanguageModelSession(model: contentTaggingModel)
        let stream = session.streamResponse(
            to: landmark.description,
            generating: TaggingResponse.self,
            options: GenerationOptions(sampling: .greedy)
        )

        for try await newTags in stream {
            generatedTags = newTags.content
        }
    } catch {
        Logging.general.error("\(error.localizedDescription)")
    }
}
```

## Integrate with other framework features

You can combine these generative model features with other Apple frameworks. For example, the `LocationLookup` class uses MapKit to search for addresses for points of interest, illustrating how to combine model-generated content with weather information and location data for trip planning.

MapKit reference:
[https://developer.apple.com/documentation/MapKit](https://developer.apple.com/documentation/MapKit)

```swift
@Observable
@MainActor
final class LocationLookup {
    private(set) var item: MKMapItem?
    private(set) var temperatureString: String?

    func performLookup(location: String) {
        Task {
            let item = await self.mapItem(atLocation: location)
            if let location = item?.location {
                self.temperatureString = await self.weather(atLocation: location)
            }
        }
    }

    private func mapItem(atLocation location: String) async -> MKMapItem? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = location
        let search = MKLocalSearch(request: request)

        do {
            return try await search.start().mapItems.first
        } catch {
            Logging.general.error("Failed to look up location: \(location). Error: \(error)")
        }

        return nil
    }
}
```

The model generates location names as text, and `LocationLookup` converts them into real, mappable locations using MapKit’s natural language search.

## See Also

* Generating content and performing tasks with Foundation Models
  [https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
* Improving the safety of generative model output
  [https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output)
* Supporting languages and locales with Foundation Models
  [https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models)
* `SystemLanguageModel` (class)
  [https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel)
* `SystemLanguageModel.UseCase` (struct)
  [https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/usecase](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/usecase)
