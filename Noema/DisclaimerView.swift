import SwiftUI

struct DisclaimerView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Group {
                    Text("Web Search Tool Calls")
                        .font(.headline)
                    Text("Tool calling isn't perfect. Although Noema implements many methods of detecting and instructing models to use tools, not all LLMs will follow instructions and some might not call them correctly or at all. Tool calling heavily depends on model pre-training and will get better as time passes.")
                }
                Group {
                    Text("Model Detection Limitations")
                        .font(.headline)
                    Text("Some models do not provide the system prompts needed for Noema to detect and configure them properly. These models may be unusable until they include appropriate metadata or support.")
                }
                Group {
                    Text("RAM Safety Checks")
                        .font(.headline)
                    Text("Noema attempts to gauge available memory to prevent models from exceeding device limits. These checks may occasionally miss risky situations and allow a model to crash your app, or they may be overly conservative and block a model that could have run fine.")
                }
                Group {
                    Text("Large Model Downloads")
                        .font(.headline)
                    Text("Many models are several gigabytes in size and require a stable connection and sufficient storage. Downloads can fail or take a long time on slow networks or devices with limited space.")
                }
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("Notes")
    }
}

#Preview {
    DisclaimerView()
}
