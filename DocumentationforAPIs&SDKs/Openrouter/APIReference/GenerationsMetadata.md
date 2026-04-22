# Get request & usage metadata for a generation

GET https://openrouter.ai/api/v1/generation

Reference: https://openrouter.ai/docs/api/api-reference/generations/get-generation

## OpenAPI Specification

```yaml
openapi: 3.1.0
info:
  title: OpenRouter API
  version: 1.0.0
paths:
  /generation:
    get:
      operationId: get-generation
      summary: Get request & usage metadata for a generation
      tags:
        - subpackage_generations
      parameters:
        - name: id
          in: query
          required: true
          schema:
            type: string
        - name: Authorization
          in: header
          description: API key as bearer token in Authorization header
          required: true
          schema:
            type: string
      responses:
        '200':
          description: Returns the request metadata for this generation
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/Generations_getGeneration_Response_200'
        '401':
          description: Unauthorized - Authentication required or invalid credentials
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/UnauthorizedResponse'
        '402':
          description: Payment Required - Insufficient credits or quota to complete request
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/PaymentRequiredResponse'
        '404':
          description: Not Found - Generation not found
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/NotFoundResponse'
        '429':
          description: Too Many Requests - Rate limit exceeded
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/TooManyRequestsResponse'
        '500':
          description: Internal Server Error - Unexpected server error
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/InternalServerResponse'
        '502':
          description: Bad Gateway - Provider/upstream API failure
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/BadGatewayResponse'
servers:
  - url: https://openrouter.ai/api/v1
components:
  schemas:
    GenerationGetResponsesContentApplicationJsonSchemaDataApiType:
      type: string
      enum:
        - completions
        - embeddings
      description: Type of API used for the generation
      title: GenerationGetResponsesContentApplicationJsonSchemaDataApiType
    GenerationGetResponsesContentApplicationJsonSchemaDataProviderResponsesItemsProviderName:
      type: string
      enum:
        - AnyScale
        - Atoma
        - Cent-ML
        - CrofAI
        - Enfer
        - GoPomelo
        - HuggingFace
        - Hyperbolic 2
        - InoCloud
        - Kluster
        - Lambda
        - Lepton
        - Lynn 2
        - Lynn
        - Mancer
        - Meta
        - Modal
        - Nineteen
        - OctoAI
        - Recursal
        - Reflection
        - Replicate
        - SambaNova 2
        - SF Compute
        - Targon
        - Together 2
        - Ubicloud
        - 01.AI
        - AI21
        - AionLabs
        - Alibaba
        - Ambient
        - Amazon Bedrock
        - Amazon Nova
        - Anthropic
        - Arcee AI
        - AtlasCloud
        - Avian
        - Azure
        - BaseTen
        - BytePlus
        - Black Forest Labs
        - Cerebras
        - Chutes
        - Cirrascale
        - Clarifai
        - Cloudflare
        - Cohere
        - Crusoe
        - DeepInfra
        - DeepSeek
        - Featherless
        - Fireworks
        - Friendli
        - GMICloud
        - Google
        - Google AI Studio
        - Groq
        - Hyperbolic
        - Inception
        - Inceptron
        - InferenceNet
        - Ionstream
        - Infermatic
        - Io Net
        - Inflection
        - Liquid
        - Mara
        - Mancer 2
        - Minimax
        - ModelRun
        - Mistral
        - Modular
        - Moonshot AI
        - Morph
        - NCompass
        - Nebius
        - NextBit
        - Novita
        - Nvidia
        - OpenAI
        - OpenInference
        - Parasail
        - Perplexity
        - Phala
        - Relace
        - SambaNova
        - Seed
        - SiliconFlow
        - Sourceful
        - StepFun
        - Stealth
        - StreamLake
        - Switchpoint
        - Together
        - Upstage
        - Venice
        - WandB
        - Xiaomi
        - xAI
        - Z.AI
        - FakeProvider
      title: >-
        GenerationGetResponsesContentApplicationJsonSchemaDataProviderResponsesItemsProviderName
    GenerationGetResponsesContentApplicationJsonSchemaDataProviderResponsesItems:
      type: object
      properties:
        id:
          type: string
        endpoint_id:
          type: string
        model_permaslug:
          type: string
        provider_name:
          $ref: >-
            #/components/schemas/GenerationGetResponsesContentApplicationJsonSchemaDataProviderResponsesItemsProviderName
        status:
          type:
            - number
            - 'null'
          format: double
        latency:
          type: number
          format: double
        is_byok:
          type: boolean
      required:
        - status
      title: >-
        GenerationGetResponsesContentApplicationJsonSchemaDataProviderResponsesItems
    GenerationGetResponsesContentApplicationJsonSchemaData:
      type: object
      properties:
        id:
          type: string
          description: Unique identifier for the generation
        upstream_id:
          type:
            - string
            - 'null'
          description: Upstream provider's identifier for this generation
        total_cost:
          type: number
          format: double
          description: Total cost of the generation in USD
        cache_discount:
          type:
            - number
            - 'null'
          format: double
          description: Discount applied due to caching
        upstream_inference_cost:
          type:
            - number
            - 'null'
          format: double
          description: Cost charged by the upstream provider
        created_at:
          type: string
          description: ISO 8601 timestamp of when the generation was created
        model:
          type: string
          description: Model used for the generation
        app_id:
          type:
            - number
            - 'null'
          format: double
          description: ID of the app that made the request
        streamed:
          type:
            - boolean
            - 'null'
          description: Whether the response was streamed
        cancelled:
          type:
            - boolean
            - 'null'
          description: Whether the generation was cancelled
        provider_name:
          type:
            - string
            - 'null'
          description: Name of the provider that served the request
        latency:
          type:
            - number
            - 'null'
          format: double
          description: Total latency in milliseconds
        moderation_latency:
          type:
            - number
            - 'null'
          format: double
          description: Moderation latency in milliseconds
        generation_time:
          type:
            - number
            - 'null'
          format: double
          description: Time taken for generation in milliseconds
        finish_reason:
          type:
            - string
            - 'null'
          description: Reason the generation finished
        tokens_prompt:
          type:
            - number
            - 'null'
          format: double
          description: Number of tokens in the prompt
        tokens_completion:
          type:
            - number
            - 'null'
          format: double
          description: Number of tokens in the completion
        native_tokens_prompt:
          type:
            - number
            - 'null'
          format: double
          description: Native prompt tokens as reported by provider
        native_tokens_completion:
          type:
            - number
            - 'null'
          format: double
          description: Native completion tokens as reported by provider
        native_tokens_completion_images:
          type:
            - number
            - 'null'
          format: double
          description: Native completion image tokens as reported by provider
        native_tokens_reasoning:
          type:
            - number
            - 'null'
          format: double
          description: Native reasoning tokens as reported by provider
        native_tokens_cached:
          type:
            - number
            - 'null'
          format: double
          description: Native cached tokens as reported by provider
        num_media_prompt:
          type:
            - number
            - 'null'
          format: double
          description: Number of media items in the prompt
        num_input_audio_prompt:
          type:
            - number
            - 'null'
          format: double
          description: Number of audio inputs in the prompt
        num_media_completion:
          type:
            - number
            - 'null'
          format: double
          description: Number of media items in the completion
        num_search_results:
          type:
            - number
            - 'null'
          format: double
          description: Number of search results included
        origin:
          type: string
          description: Origin URL of the request
        usage:
          type: number
          format: double
          description: Usage amount in USD
        is_byok:
          type: boolean
          description: Whether this used bring-your-own-key
        native_finish_reason:
          type:
            - string
            - 'null'
          description: Native finish reason as reported by provider
        external_user:
          type:
            - string
            - 'null'
          description: External user identifier
        api_type:
          oneOf:
            - $ref: >-
                #/components/schemas/GenerationGetResponsesContentApplicationJsonSchemaDataApiType
            - type: 'null'
          description: Type of API used for the generation
        router:
          type:
            - string
            - 'null'
          description: Router used for the request (e.g., openrouter/auto)
        provider_responses:
          type:
            - array
            - 'null'
          items:
            $ref: >-
              #/components/schemas/GenerationGetResponsesContentApplicationJsonSchemaDataProviderResponsesItems
          description: >-
            List of provider responses for this generation, including fallback
            attempts
      required:
        - id
        - upstream_id
        - total_cost
        - cache_discount
        - upstream_inference_cost
        - created_at
        - model
        - app_id
        - streamed
        - cancelled
        - provider_name
        - latency
        - moderation_latency
        - generation_time
        - finish_reason
        - tokens_prompt
        - tokens_completion
        - native_tokens_prompt
        - native_tokens_completion
        - native_tokens_completion_images
        - native_tokens_reasoning
        - native_tokens_cached
        - num_media_prompt
        - num_input_audio_prompt
        - num_media_completion
        - num_search_results
        - origin
        - usage
        - is_byok
        - native_finish_reason
        - external_user
        - api_type
        - router
        - provider_responses
      description: Generation data
      title: GenerationGetResponsesContentApplicationJsonSchemaData
    Generations_getGeneration_Response_200:
      type: object
      properties:
        data:
          $ref: >-
            #/components/schemas/GenerationGetResponsesContentApplicationJsonSchemaData
          description: Generation data
      required:
        - data
      description: Generation response
      title: Generations_getGeneration_Response_200
    UnauthorizedResponseErrorData:
      type: object
      properties:
        code:
          type: integer
        message:
          type: string
        metadata:
          type:
            - object
            - 'null'
          additionalProperties:
            description: Any type
      required:
        - code
        - message
      description: Error data for UnauthorizedResponse
      title: UnauthorizedResponseErrorData
    UnauthorizedResponse:
      type: object
      properties:
        error:
          $ref: '#/components/schemas/UnauthorizedResponseErrorData'
        user_id:
          type:
            - string
            - 'null'
      required:
        - error
      description: Unauthorized - Authentication required or invalid credentials
      title: UnauthorizedResponse
    PaymentRequiredResponseErrorData:
      type: object
      properties:
        code:
          type: integer
        message:
          type: string
        metadata:
          type:
            - object
            - 'null'
          additionalProperties:
            description: Any type
      required:
        - code
        - message
      description: Error data for PaymentRequiredResponse
      title: PaymentRequiredResponseErrorData
    PaymentRequiredResponse:
      type: object
      properties:
        error:
          $ref: '#/components/schemas/PaymentRequiredResponseErrorData'
        user_id:
          type:
            - string
            - 'null'
      required:
        - error
      description: Payment Required - Insufficient credits or quota to complete request
      title: PaymentRequiredResponse
    NotFoundResponseErrorData:
      type: object
      properties:
        code:
          type: integer
        message:
          type: string
        metadata:
          type:
            - object
            - 'null'
          additionalProperties:
            description: Any type
      required:
        - code
        - message
      description: Error data for NotFoundResponse
      title: NotFoundResponseErrorData
    NotFoundResponse:
      type: object
      properties:
        error:
          $ref: '#/components/schemas/NotFoundResponseErrorData'
        user_id:
          type:
            - string
            - 'null'
      required:
        - error
      description: Not Found - Resource does not exist
      title: NotFoundResponse
    TooManyRequestsResponseErrorData:
      type: object
      properties:
        code:
          type: integer
        message:
          type: string
        metadata:
          type:
            - object
            - 'null'
          additionalProperties:
            description: Any type
      required:
        - code
        - message
      description: Error data for TooManyRequestsResponse
      title: TooManyRequestsResponseErrorData
    TooManyRequestsResponse:
      type: object
      properties:
        error:
          $ref: '#/components/schemas/TooManyRequestsResponseErrorData'
        user_id:
          type:
            - string
            - 'null'
      required:
        - error
      description: Too Many Requests - Rate limit exceeded
      title: TooManyRequestsResponse
    InternalServerResponseErrorData:
      type: object
      properties:
        code:
          type: integer
        message:
          type: string
        metadata:
          type:
            - object
            - 'null'
          additionalProperties:
            description: Any type
      required:
        - code
        - message
      description: Error data for InternalServerResponse
      title: InternalServerResponseErrorData
    InternalServerResponse:
      type: object
      properties:
        error:
          $ref: '#/components/schemas/InternalServerResponseErrorData'
        user_id:
          type:
            - string
            - 'null'
      required:
        - error
      description: Internal Server Error - Unexpected server error
      title: InternalServerResponse
    BadGatewayResponseErrorData:
      type: object
      properties:
        code:
          type: integer
        message:
          type: string
        metadata:
          type:
            - object
            - 'null'
          additionalProperties:
            description: Any type
      required:
        - code
        - message
      description: Error data for BadGatewayResponse
      title: BadGatewayResponseErrorData
    BadGatewayResponse:
      type: object
      properties:
        error:
          $ref: '#/components/schemas/BadGatewayResponseErrorData'
        user_id:
          type:
            - string
            - 'null'
      required:
        - error
      description: Bad Gateway - Provider/upstream API failure
      title: BadGatewayResponse
  securitySchemes:
    apiKey:
      type: http
      scheme: bearer
      description: API key as bearer token in Authorization header

```

## SDK Code Examples

```python
import requests

url = "https://openrouter.ai/api/v1/generation"

querystring = {"id":"id"}

headers = {"Authorization": "Bearer <token>"}

response = requests.get(url, headers=headers, params=querystring)

print(response.json())
```

```javascript
const url = 'https://openrouter.ai/api/v1/generation?id=id';
const options = {method: 'GET', headers: {Authorization: 'Bearer <token>'}};

try {
  const response = await fetch(url, options);
  const data = await response.json();
  console.log(data);
} catch (error) {
  console.error(error);
}
```

```go
package main

import (
	"fmt"
	"net/http"
	"io"
)

func main() {

	url := "https://openrouter.ai/api/v1/generation?id=id"

	req, _ := http.NewRequest("GET", url, nil)

	req.Header.Add("Authorization", "Bearer <token>")

	res, _ := http.DefaultClient.Do(req)

	defer res.Body.Close()
	body, _ := io.ReadAll(res.Body)

	fmt.Println(res)
	fmt.Println(string(body))

}
```

```ruby
require 'uri'
require 'net/http'

url = URI("https://openrouter.ai/api/v1/generation?id=id")

http = Net::HTTP.new(url.host, url.port)
http.use_ssl = true

request = Net::HTTP::Get.new(url)
request["Authorization"] = 'Bearer <token>'

response = http.request(request)
puts response.read_body
```

```java
import com.mashape.unirest.http.HttpResponse;
import com.mashape.unirest.http.Unirest;

HttpResponse<String> response = Unirest.get("https://openrouter.ai/api/v1/generation?id=id")
  .header("Authorization", "Bearer <token>")
  .asString();
```

```php
<?php
require_once('vendor/autoload.php');

$client = new \GuzzleHttp\Client();

$response = $client->request('GET', 'https://openrouter.ai/api/v1/generation?id=id', [
  'headers' => [
    'Authorization' => 'Bearer <token>',
  ],
]);

echo $response->getBody();
```

```csharp
using RestSharp;

var client = new RestClient("https://openrouter.ai/api/v1/generation?id=id");
var request = new RestRequest(Method.GET);
request.AddHeader("Authorization", "Bearer <token>");
IRestResponse response = client.Execute(request);
```

```swift
import Foundation

let headers = ["Authorization": "Bearer <token>"]

let request = NSMutableURLRequest(url: NSURL(string: "https://openrouter.ai/api/v1/generation?id=id")! as URL,
                                        cachePolicy: .useProtocolCachePolicy,
                                    timeoutInterval: 10.0)
request.httpMethod = "GET"
request.allHTTPHeaderFields = headers

let session = URLSession.shared
let dataTask = session.dataTask(with: request as URLRequest, completionHandler: { (data, response, error) -> Void in
  if (error != nil) {
    print(error as Any)
  } else {
    let httpResponse = response as? HTTPURLResponse
    print(httpResponse)
  }
})

dataTask.resume()
```