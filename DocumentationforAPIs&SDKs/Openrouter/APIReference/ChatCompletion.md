# Create a chat completion

POST https://openrouter.ai/api/v1/chat/completions
Content-Type: application/json

Sends a request for a model response for the given chat conversation. Supports both streaming and non-streaming modes.

Reference: https://openrouter.ai/docs/api/api-reference/chat/send-chat-completion-request

## OpenAPI Specification

```yaml
openapi: 3.1.0
info:
  title: OpenRouter API
  version: 1.0.0
paths:
  /chat/completions:
    post:
      operationId: send-chat-completion-request
      summary: Create a chat completion
      description: >-
        Sends a request for a model response for the given chat conversation.
        Supports both streaming and non-streaming modes.
      tags:
        - subpackage_chat
      parameters:
        - name: Authorization
          in: header
          description: API key as bearer token in Authorization header
          required: true
          schema:
            type: string
      responses:
        '200':
          description: Successful chat completion response
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ChatResponse'
        '400':
          description: Bad Request - Invalid request parameters or malformed input
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/BadRequestResponse'
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
          description: Not Found - Resource does not exist
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/NotFoundResponse'
        '408':
          description: Request Timeout - Operation exceeded time limit
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/RequestTimeoutResponse'
        '413':
          description: Payload Too Large - Request payload exceeds size limits
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/PayloadTooLargeResponse'
        '422':
          description: Unprocessable Entity - Semantic validation failure
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/UnprocessableEntityResponse'
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
        '503':
          description: Service Unavailable - Service temporarily unavailable
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/ServiceUnavailableResponse'
      requestBody:
        content:
          application/json:
            schema:
              $ref: '#/components/schemas/ChatGenerationParams'
servers:
  - url: https://openrouter.ai/api/v1
components:
  schemas:
    DataCollection:
      type: string
      enum:
        - deny
        - allow
      description: >-
        Data collection setting. If no available model provider meets the
        requirement, your request will return an error.

        - allow: (default) allow providers which store user data non-transiently
        and may train on it


        - deny: use only providers which do not collect user data.
      title: DataCollection
    ProviderName:
      type: string
      enum:
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
      title: ProviderName
    ChatGenerationParamsProviderOrderItems:
      oneOf:
        - $ref: '#/components/schemas/ProviderName'
        - type: string
      title: ChatGenerationParamsProviderOrderItems
    ChatGenerationParamsProviderOnlyItems:
      oneOf:
        - $ref: '#/components/schemas/ProviderName'
        - type: string
      title: ChatGenerationParamsProviderOnlyItems
    ChatGenerationParamsProviderIgnoreItems:
      oneOf:
        - $ref: '#/components/schemas/ProviderName'
        - type: string
      title: ChatGenerationParamsProviderIgnoreItems
    Quantization:
      type: string
      enum:
        - int4
        - int8
        - fp4
        - fp6
        - fp8
        - fp16
        - bf16
        - fp32
        - unknown
      title: Quantization
    ChatGenerationParamsProviderSort:
      type: object
      properties: {}
      title: ChatGenerationParamsProviderSort
    BigNumberUnion:
      type: string
      description: Price per million prompt tokens
      title: BigNumberUnion
    ChatGenerationParamsProviderMaxPriceCompletion:
      type: object
      properties: {}
      title: ChatGenerationParamsProviderMaxPriceCompletion
    ChatGenerationParamsProviderMaxPriceImage:
      type: object
      properties: {}
      title: ChatGenerationParamsProviderMaxPriceImage
    ChatGenerationParamsProviderMaxPriceAudio:
      type: object
      properties: {}
      title: ChatGenerationParamsProviderMaxPriceAudio
    ChatGenerationParamsProviderMaxPriceRequest:
      type: object
      properties: {}
      title: ChatGenerationParamsProviderMaxPriceRequest
    ChatGenerationParamsProviderMaxPrice:
      type: object
      properties:
        prompt:
          $ref: '#/components/schemas/BigNumberUnion'
        completion:
          $ref: '#/components/schemas/ChatGenerationParamsProviderMaxPriceCompletion'
        image:
          $ref: '#/components/schemas/ChatGenerationParamsProviderMaxPriceImage'
        audio:
          $ref: '#/components/schemas/ChatGenerationParamsProviderMaxPriceAudio'
        request:
          $ref: '#/components/schemas/ChatGenerationParamsProviderMaxPriceRequest'
      description: >-
        The object specifying the maximum price you want to pay for this
        request. USD price per million tokens, for prompt and completion.
      title: ChatGenerationParamsProviderMaxPrice
    PercentileThroughputCutoffs:
      type: object
      properties:
        p50:
          type:
            - number
            - 'null'
          format: double
          description: Minimum p50 throughput (tokens/sec)
        p75:
          type:
            - number
            - 'null'
          format: double
          description: Minimum p75 throughput (tokens/sec)
        p90:
          type:
            - number
            - 'null'
          format: double
          description: Minimum p90 throughput (tokens/sec)
        p99:
          type:
            - number
            - 'null'
          format: double
          description: Minimum p99 throughput (tokens/sec)
      description: >-
        Percentile-based throughput cutoffs. All specified cutoffs must be met
        for an endpoint to be preferred.
      title: PercentileThroughputCutoffs
    PreferredMinThroughput:
      oneOf:
        - type: number
          format: double
        - $ref: '#/components/schemas/PercentileThroughputCutoffs'
        - description: Any type
      description: >-
        Preferred minimum throughput (in tokens per second). Can be a number
        (applies to p50) or an object with percentile-specific cutoffs.
        Endpoints below the threshold(s) may still be used, but are
        deprioritized in routing. When using fallback models, this may cause a
        fallback model to be used instead of the primary model if it meets the
        threshold.
      title: PreferredMinThroughput
    PercentileLatencyCutoffs:
      type: object
      properties:
        p50:
          type:
            - number
            - 'null'
          format: double
          description: Maximum p50 latency (seconds)
        p75:
          type:
            - number
            - 'null'
          format: double
          description: Maximum p75 latency (seconds)
        p90:
          type:
            - number
            - 'null'
          format: double
          description: Maximum p90 latency (seconds)
        p99:
          type:
            - number
            - 'null'
          format: double
          description: Maximum p99 latency (seconds)
      description: >-
        Percentile-based latency cutoffs. All specified cutoffs must be met for
        an endpoint to be preferred.
      title: PercentileLatencyCutoffs
    PreferredMaxLatency:
      oneOf:
        - type: number
          format: double
        - $ref: '#/components/schemas/PercentileLatencyCutoffs'
        - description: Any type
      description: >-
        Preferred maximum latency (in seconds). Can be a number (applies to p50)
        or an object with percentile-specific cutoffs. Endpoints above the
        threshold(s) may still be used, but are deprioritized in routing. When
        using fallback models, this may cause a fallback model to be used
        instead of the primary model if it meets the threshold.
      title: PreferredMaxLatency
    ChatGenerationParamsProvider:
      type: object
      properties:
        allow_fallbacks:
          type:
            - boolean
            - 'null'
          description: >
            Whether to allow backup providers to serve requests

            - true: (default) when the primary provider (or your custom
            providers in "order") is unavailable, use the next best provider.

            - false: use only the primary/custom provider, and return the
            upstream error if it's unavailable.
        require_parameters:
          type:
            - boolean
            - 'null'
          description: >-
            Whether to filter providers to only those that support the
            parameters you've provided. If this setting is omitted or set to
            false, then providers will receive only the parameters they support,
            and ignore the rest.
        data_collection:
          $ref: '#/components/schemas/DataCollection'
        zdr:
          type:
            - boolean
            - 'null'
          description: >-
            Whether to restrict routing to only ZDR (Zero Data Retention)
            endpoints. When true, only endpoints that do not retain prompts will
            be used.
        enforce_distillable_text:
          type:
            - boolean
            - 'null'
          description: >-
            Whether to restrict routing to only models that allow text
            distillation. When true, only models where the author has allowed
            distillation will be used.
        order:
          type:
            - array
            - 'null'
          items:
            $ref: '#/components/schemas/ChatGenerationParamsProviderOrderItems'
          description: >-
            An ordered list of provider slugs. The router will attempt to use
            the first provider in the subset of this list that supports your
            requested model, and fall back to the next if it is unavailable. If
            no providers are available, the request will fail with an error
            message.
        only:
          type:
            - array
            - 'null'
          items:
            $ref: '#/components/schemas/ChatGenerationParamsProviderOnlyItems'
          description: >-
            List of provider slugs to allow. If provided, this list is merged
            with your account-wide allowed provider settings for this request.
        ignore:
          type:
            - array
            - 'null'
          items:
            $ref: '#/components/schemas/ChatGenerationParamsProviderIgnoreItems'
          description: >-
            List of provider slugs to ignore. If provided, this list is merged
            with your account-wide ignored provider settings for this request.
        quantizations:
          type:
            - array
            - 'null'
          items:
            $ref: '#/components/schemas/Quantization'
          description: A list of quantization levels to filter the provider by.
        sort:
          $ref: '#/components/schemas/ChatGenerationParamsProviderSort'
        max_price:
          $ref: '#/components/schemas/ChatGenerationParamsProviderMaxPrice'
          description: >-
            The object specifying the maximum price you want to pay for this
            request. USD price per million tokens, for prompt and completion.
        preferred_min_throughput:
          $ref: '#/components/schemas/PreferredMinThroughput'
        preferred_max_latency:
          $ref: '#/components/schemas/PreferredMaxLatency'
      description: >-
        When multiple model providers are available, optionally indicate your
        routing preference.
      title: ChatGenerationParamsProvider
    ChatGenerationParamsPluginsItemsOneOf0Id:
      type: string
      enum:
        - auto-router
      title: ChatGenerationParamsPluginsItemsOneOf0Id
    ChatGenerationParamsPluginsItems0:
      type: object
      properties:
        id:
          $ref: '#/components/schemas/ChatGenerationParamsPluginsItemsOneOf0Id'
        enabled:
          type: boolean
          description: >-
            Set to false to disable the auto-router plugin for this request.
            Defaults to true.
        allowed_models:
          type: array
          items:
            type: string
          description: >-
            List of model patterns to filter which models the auto-router can
            route between. Supports wildcards (e.g., "anthropic/*" matches all
            Anthropic models). When not specified, uses the default supported
            models list.
      required:
        - id
      title: ChatGenerationParamsPluginsItems0
    ChatGenerationParamsPluginsItemsOneOf1Id:
      type: string
      enum:
        - moderation
      title: ChatGenerationParamsPluginsItemsOneOf1Id
    ChatGenerationParamsPluginsItems1:
      type: object
      properties:
        id:
          $ref: '#/components/schemas/ChatGenerationParamsPluginsItemsOneOf1Id'
      required:
        - id
      title: ChatGenerationParamsPluginsItems1
    ChatGenerationParamsPluginsItemsOneOf2Id:
      type: string
      enum:
        - web
      title: ChatGenerationParamsPluginsItemsOneOf2Id
    WebSearchEngine:
      type: string
      enum:
        - native
        - exa
      description: The search engine to use for web search.
      title: WebSearchEngine
    ChatGenerationParamsPluginsItems2:
      type: object
      properties:
        id:
          $ref: '#/components/schemas/ChatGenerationParamsPluginsItemsOneOf2Id'
        enabled:
          type: boolean
          description: >-
            Set to false to disable the web-search plugin for this request.
            Defaults to true.
        max_results:
          type: number
          format: double
        search_prompt:
          type: string
        engine:
          $ref: '#/components/schemas/WebSearchEngine'
      required:
        - id
      title: ChatGenerationParamsPluginsItems2
    ChatGenerationParamsPluginsItemsOneOf3Id:
      type: string
      enum:
        - file-parser
      title: ChatGenerationParamsPluginsItemsOneOf3Id
    PDFParserEngine:
      type: string
      enum:
        - mistral-ocr
        - pdf-text
        - native
      description: The engine to use for parsing PDF files.
      title: PDFParserEngine
    PDFParserOptions:
      type: object
      properties:
        engine:
          $ref: '#/components/schemas/PDFParserEngine'
      description: Options for PDF parsing.
      title: PDFParserOptions
    ChatGenerationParamsPluginsItems3:
      type: object
      properties:
        id:
          $ref: '#/components/schemas/ChatGenerationParamsPluginsItemsOneOf3Id'
        enabled:
          type: boolean
          description: >-
            Set to false to disable the file-parser plugin for this request.
            Defaults to true.
        pdf:
          $ref: '#/components/schemas/PDFParserOptions'
      required:
        - id
      title: ChatGenerationParamsPluginsItems3
    ChatGenerationParamsPluginsItemsOneOf4Id:
      type: string
      enum:
        - response-healing
      title: ChatGenerationParamsPluginsItemsOneOf4Id
    ChatGenerationParamsPluginsItems4:
      type: object
      properties:
        id:
          $ref: '#/components/schemas/ChatGenerationParamsPluginsItemsOneOf4Id'
        enabled:
          type: boolean
          description: >-
            Set to false to disable the response-healing plugin for this
            request. Defaults to true.
      required:
        - id
      title: ChatGenerationParamsPluginsItems4
    ChatGenerationParamsPluginsItems:
      oneOf:
        - $ref: '#/components/schemas/ChatGenerationParamsPluginsItems0'
        - $ref: '#/components/schemas/ChatGenerationParamsPluginsItems1'
        - $ref: '#/components/schemas/ChatGenerationParamsPluginsItems2'
        - $ref: '#/components/schemas/ChatGenerationParamsPluginsItems3'
        - $ref: '#/components/schemas/ChatGenerationParamsPluginsItems4'
      title: ChatGenerationParamsPluginsItems
    ChatGenerationParamsTrace:
      type: object
      properties:
        trace_id:
          type: string
        trace_name:
          type: string
        span_name:
          type: string
        generation_name:
          type: string
        parent_span_id:
          type: string
      description: >-
        Metadata for observability and tracing. Known keys (trace_id,
        trace_name, span_name, generation_name, parent_span_id) have special
        handling. Additional keys are passed through as custom metadata to
        configured broadcast destinations.
      title: ChatGenerationParamsTrace
    SystemMessageRole:
      type: string
      enum:
        - system
      title: SystemMessageRole
    ChatMessageContentItemTextType:
      type: string
      enum:
        - text
      title: ChatMessageContentItemTextType
    ChatMessageContentItemCacheControlType:
      type: string
      enum:
        - ephemeral
      title: ChatMessageContentItemCacheControlType
    ChatMessageContentItemCacheControlTtl:
      type: string
      enum:
        - 5m
        - 1h
      title: ChatMessageContentItemCacheControlTtl
    ChatMessageContentItemCacheControl:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ChatMessageContentItemCacheControlType'
        ttl:
          $ref: '#/components/schemas/ChatMessageContentItemCacheControlTtl'
      required:
        - type
      description: Cache control for the content part
      title: ChatMessageContentItemCacheControl
    ChatMessageContentItemText:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ChatMessageContentItemTextType'
        text:
          type: string
        cache_control:
          $ref: '#/components/schemas/ChatMessageContentItemCacheControl'
      required:
        - type
        - text
      description: Text content part
      title: ChatMessageContentItemText
    SystemMessageContent1:
      type: array
      items:
        $ref: '#/components/schemas/ChatMessageContentItemText'
      title: SystemMessageContent1
    SystemMessageContent:
      oneOf:
        - type: string
        - $ref: '#/components/schemas/SystemMessageContent1'
      description: System message content
      title: SystemMessageContent
    SystemMessage:
      type: object
      properties:
        role:
          $ref: '#/components/schemas/SystemMessageRole'
        content:
          $ref: '#/components/schemas/SystemMessageContent'
          description: System message content
        name:
          type: string
          description: Optional name for the system message
      required:
        - role
        - content
      description: System message for setting behavior
      title: SystemMessage
    UserMessageRole:
      type: string
      enum:
        - user
      title: UserMessageRole
    ChatMessageContentItemImageType:
      type: string
      enum:
        - image_url
      title: ChatMessageContentItemImageType
    ChatMessageContentItemImageImageUrlDetail:
      type: string
      enum:
        - auto
        - low
        - high
      description: Image detail level for vision models
      title: ChatMessageContentItemImageImageUrlDetail
    ChatMessageContentItemImageImageUrl:
      type: object
      properties:
        url:
          type: string
          description: 'URL of the image (data: URLs supported)'
        detail:
          $ref: '#/components/schemas/ChatMessageContentItemImageImageUrlDetail'
          description: Image detail level for vision models
      required:
        - url
      title: ChatMessageContentItemImageImageUrl
    ChatMessageContentItemImage:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ChatMessageContentItemImageType'
        image_url:
          $ref: '#/components/schemas/ChatMessageContentItemImageImageUrl'
      required:
        - type
        - image_url
      description: Image content part for vision models
      title: ChatMessageContentItemImage
    ChatMessageContentItemAudioType:
      type: string
      enum:
        - input_audio
      title: ChatMessageContentItemAudioType
    ChatMessageContentItemAudioInputAudio:
      type: object
      properties:
        data:
          type: string
          description: Base64 encoded audio data
        format:
          type: string
          description: >-
            Audio format (e.g., wav, mp3, flac, m4a, ogg, aiff, aac, pcm16,
            pcm24). Supported formats vary by provider.
      required:
        - data
        - format
      title: ChatMessageContentItemAudioInputAudio
    ChatMessageContentItemAudio:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ChatMessageContentItemAudioType'
        input_audio:
          $ref: '#/components/schemas/ChatMessageContentItemAudioInputAudio'
      required:
        - type
        - input_audio
      description: Audio input content part. Supported audio formats vary by provider.
      title: ChatMessageContentItemAudio
    ChatMessageContentItemVideoLegacyType:
      type: string
      enum:
        - input_video
      title: ChatMessageContentItemVideoLegacyType
    VideoInput:
      type: object
      properties:
        url:
          type: string
          description: 'URL of the video (data: URLs supported)'
      required:
        - url
      description: Video input object
      title: VideoInput
    ChatMessageContentItemVideoLegacy:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ChatMessageContentItemVideoLegacyType'
        video_url:
          $ref: '#/components/schemas/VideoInput'
      required:
        - type
        - video_url
      description: Video input content part (legacy format - deprecated)
      title: ChatMessageContentItemVideoLegacy
    ChatMessageContentItemVideoType:
      type: string
      enum:
        - video_url
      title: ChatMessageContentItemVideoType
    ChatMessageContentItemVideo:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ChatMessageContentItemVideoType'
        video_url:
          $ref: '#/components/schemas/VideoInput'
      required:
        - type
        - video_url
      description: Video input content part
      title: ChatMessageContentItemVideo
    ChatMessageContentItem3:
      oneOf:
        - $ref: '#/components/schemas/ChatMessageContentItemVideoLegacy'
        - $ref: '#/components/schemas/ChatMessageContentItemVideo'
      title: ChatMessageContentItem3
    ChatMessageContentItemFileType:
      type: string
      enum:
        - file
      title: ChatMessageContentItemFileType
    ChatMessageContentItemFileFile:
      type: object
      properties:
        file_data:
          type: string
          description: File content as base64 data URL or URL
        file_id:
          type: string
          description: File ID for previously uploaded files
        filename:
          type: string
          description: Original filename
      title: ChatMessageContentItemFileFile
    ChatMessageContentItemFile:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ChatMessageContentItemFileType'
        file:
          $ref: '#/components/schemas/ChatMessageContentItemFileFile'
      required:
        - type
        - file
      description: File content part for document processing
      title: ChatMessageContentItemFile
    ChatMessageContentItem:
      oneOf:
        - $ref: '#/components/schemas/ChatMessageContentItemText'
        - $ref: '#/components/schemas/ChatMessageContentItemImage'
        - $ref: '#/components/schemas/ChatMessageContentItemAudio'
        - $ref: '#/components/schemas/ChatMessageContentItem3'
        - $ref: '#/components/schemas/ChatMessageContentItemFile'
      description: Content part for chat completion messages
      title: ChatMessageContentItem
    UserMessageContent1:
      type: array
      items:
        $ref: '#/components/schemas/ChatMessageContentItem'
      title: UserMessageContent1
    UserMessageContent:
      oneOf:
        - type: string
        - $ref: '#/components/schemas/UserMessageContent1'
      description: User message content
      title: UserMessageContent
    UserMessage:
      type: object
      properties:
        role:
          $ref: '#/components/schemas/UserMessageRole'
        content:
          $ref: '#/components/schemas/UserMessageContent'
          description: User message content
        name:
          type: string
          description: Optional name for the user
      required:
        - role
        - content
      description: User message
      title: UserMessage
    DeveloperMessageRole:
      type: string
      enum:
        - developer
      title: DeveloperMessageRole
    DeveloperMessageContent1:
      type: array
      items:
        $ref: '#/components/schemas/ChatMessageContentItemText'
      title: DeveloperMessageContent1
    DeveloperMessageContent:
      oneOf:
        - type: string
        - $ref: '#/components/schemas/DeveloperMessageContent1'
      description: Developer message content
      title: DeveloperMessageContent
    DeveloperMessage:
      type: object
      properties:
        role:
          $ref: '#/components/schemas/DeveloperMessageRole'
        content:
          $ref: '#/components/schemas/DeveloperMessageContent'
          description: Developer message content
        name:
          type: string
          description: Optional name for the developer message
      required:
        - role
        - content
      description: Developer message
      title: DeveloperMessage
    AssistantMessageRole:
      type: string
      enum:
        - assistant
      title: AssistantMessageRole
    AssistantMessageContent1:
      type: array
      items:
        $ref: '#/components/schemas/ChatMessageContentItem'
      title: AssistantMessageContent1
    AssistantMessageContent:
      oneOf:
        - type: string
        - $ref: '#/components/schemas/AssistantMessageContent1'
        - description: Any type
      description: Assistant message content
      title: AssistantMessageContent
    ChatMessageToolCallType:
      type: string
      enum:
        - function
      title: ChatMessageToolCallType
    ChatMessageToolCallFunction:
      type: object
      properties:
        name:
          type: string
          description: Function name to call
        arguments:
          type: string
          description: Function arguments as JSON string
      required:
        - name
        - arguments
      title: ChatMessageToolCallFunction
    ChatMessageToolCall:
      type: object
      properties:
        id:
          type: string
          description: Tool call identifier
        type:
          $ref: '#/components/schemas/ChatMessageToolCallType'
        function:
          $ref: '#/components/schemas/ChatMessageToolCallFunction'
      required:
        - id
        - type
        - function
      description: Tool call made by the assistant
      title: ChatMessageToolCall
    ReasoningDetailSummaryType:
      type: string
      enum:
        - reasoning.summary
      title: ReasoningDetailSummaryType
    ReasoningDetailSummaryFormat:
      type: string
      enum:
        - unknown
        - openai-responses-v1
        - azure-openai-responses-v1
        - xai-responses-v1
        - anthropic-claude-v1
        - google-gemini-v1
      title: ReasoningDetailSummaryFormat
    ReasoningDetailSummary:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ReasoningDetailSummaryType'
        summary:
          type: string
        id:
          type:
            - string
            - 'null'
        format:
          oneOf:
            - $ref: '#/components/schemas/ReasoningDetailSummaryFormat'
            - type: 'null'
        index:
          type: number
          format: double
      required:
        - type
        - summary
      description: Reasoning detail summary schema
      title: ReasoningDetailSummary
    ReasoningDetailEncryptedType:
      type: string
      enum:
        - reasoning.encrypted
      title: ReasoningDetailEncryptedType
    ReasoningDetailEncryptedFormat:
      type: string
      enum:
        - unknown
        - openai-responses-v1
        - azure-openai-responses-v1
        - xai-responses-v1
        - anthropic-claude-v1
        - google-gemini-v1
      title: ReasoningDetailEncryptedFormat
    ReasoningDetailEncrypted:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ReasoningDetailEncryptedType'
        data:
          type: string
        id:
          type:
            - string
            - 'null'
        format:
          oneOf:
            - $ref: '#/components/schemas/ReasoningDetailEncryptedFormat'
            - type: 'null'
        index:
          type: number
          format: double
      required:
        - type
        - data
      description: Reasoning detail encrypted schema
      title: ReasoningDetailEncrypted
    ReasoningDetailTextType:
      type: string
      enum:
        - reasoning.text
      title: ReasoningDetailTextType
    ReasoningDetailTextFormat:
      type: string
      enum:
        - unknown
        - openai-responses-v1
        - azure-openai-responses-v1
        - xai-responses-v1
        - anthropic-claude-v1
        - google-gemini-v1
      title: ReasoningDetailTextFormat
    ReasoningDetailText:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ReasoningDetailTextType'
        text:
          type:
            - string
            - 'null'
        signature:
          type:
            - string
            - 'null'
        id:
          type:
            - string
            - 'null'
        format:
          oneOf:
            - $ref: '#/components/schemas/ReasoningDetailTextFormat'
            - type: 'null'
        index:
          type: number
          format: double
      required:
        - type
      description: Reasoning detail text schema
      title: ReasoningDetailText
    ReasoningDetailUnion:
      oneOf:
        - $ref: '#/components/schemas/ReasoningDetailSummary'
        - $ref: '#/components/schemas/ReasoningDetailEncrypted'
        - $ref: '#/components/schemas/ReasoningDetailText'
      description: Reasoning detail union schema
      title: ReasoningDetailUnion
    AssistantMessageReasoningDetails:
      type: array
      items:
        $ref: '#/components/schemas/ReasoningDetailUnion'
      description: Reasoning details for extended thinking models
      title: AssistantMessageReasoningDetails
    AssistantMessageImagesItemsImageUrl:
      type: object
      properties:
        url:
          type: string
          description: URL or base64-encoded data of the generated image
      required:
        - url
      title: AssistantMessageImagesItemsImageUrl
    AssistantMessageImagesItems:
      type: object
      properties:
        image_url:
          $ref: '#/components/schemas/AssistantMessageImagesItemsImageUrl'
      required:
        - image_url
      title: AssistantMessageImagesItems
    AssistantMessageImages:
      type: array
      items:
        $ref: '#/components/schemas/AssistantMessageImagesItems'
      description: Generated images from image generation models
      title: AssistantMessageImages
    ChatCompletionAudioOutput:
      type: object
      properties:
        id:
          type: string
          description: Audio output identifier
        expires_at:
          type: number
          format: double
          description: Audio expiration timestamp
        data:
          type: string
          description: Base64 encoded audio data
        transcript:
          type: string
          description: Audio transcript
      description: Audio output data or reference
      title: ChatCompletionAudioOutput
    AssistantMessagePhase0:
      type: string
      enum:
        - commentary
      title: AssistantMessagePhase0
    AssistantMessagePhase1:
      type: string
      enum:
        - final_answer
      title: AssistantMessagePhase1
    AssistantMessagePhase:
      oneOf:
        - $ref: '#/components/schemas/AssistantMessagePhase0'
        - $ref: '#/components/schemas/AssistantMessagePhase1'
        - description: Any type
      description: >-
        The phase of an assistant message. Use `commentary` for an intermediate
        assistant message and `final_answer` for the final assistant message.
        For follow-up requests with models like `gpt-5.3-codex` and later,
        preserve and resend phase on all assistant messages. Omitting it can
        degrade performance. Not used for user messages.
      title: AssistantMessagePhase
    AssistantMessage:
      type: object
      properties:
        role:
          $ref: '#/components/schemas/AssistantMessageRole'
        content:
          $ref: '#/components/schemas/AssistantMessageContent'
          description: Assistant message content
        name:
          type: string
          description: Optional name for the assistant
        tool_calls:
          type: array
          items:
            $ref: '#/components/schemas/ChatMessageToolCall'
          description: Tool calls made by the assistant
        refusal:
          type:
            - string
            - 'null'
          description: Refusal message if content was refused
        reasoning:
          type:
            - string
            - 'null'
          description: Reasoning output
        reasoning_details:
          $ref: '#/components/schemas/AssistantMessageReasoningDetails'
        images:
          $ref: '#/components/schemas/AssistantMessageImages'
        audio:
          $ref: '#/components/schemas/ChatCompletionAudioOutput'
        phase:
          $ref: '#/components/schemas/AssistantMessagePhase'
          description: >-
            The phase of an assistant message. Use `commentary` for an
            intermediate assistant message and `final_answer` for the final
            assistant message. For follow-up requests with models like
            `gpt-5.3-codex` and later, preserve and resend phase on all
            assistant messages. Omitting it can degrade performance. Not used
            for user messages.
      required:
        - role
      description: Assistant message for requests and responses
      title: AssistantMessage
    ToolResponseMessageRole:
      type: string
      enum:
        - tool
      title: ToolResponseMessageRole
    ToolResponseMessageContent1:
      type: array
      items:
        $ref: '#/components/schemas/ChatMessageContentItem'
      title: ToolResponseMessageContent1
    ToolResponseMessageContent:
      oneOf:
        - type: string
        - $ref: '#/components/schemas/ToolResponseMessageContent1'
      description: Tool response content
      title: ToolResponseMessageContent
    ToolResponseMessage:
      type: object
      properties:
        role:
          $ref: '#/components/schemas/ToolResponseMessageRole'
        content:
          $ref: '#/components/schemas/ToolResponseMessageContent'
          description: Tool response content
        tool_call_id:
          type: string
          description: ID of the assistant message tool call this message responds to
      required:
        - role
        - content
        - tool_call_id
      description: Tool response message
      title: ToolResponseMessage
    Message:
      oneOf:
        - $ref: '#/components/schemas/SystemMessage'
        - $ref: '#/components/schemas/UserMessage'
        - $ref: '#/components/schemas/DeveloperMessage'
        - $ref: '#/components/schemas/AssistantMessage'
        - $ref: '#/components/schemas/ToolResponseMessage'
      description: Chat completion message with role-based discrimination
      title: Message
    ModelName:
      type: string
      description: Model to use for completion
      title: ModelName
    ModelNamesItems:
      type: object
      properties: {}
      title: ModelNamesItems
    ModelNames:
      type: array
      items:
        $ref: '#/components/schemas/ModelNamesItems'
      description: Models to use for completion
      title: ModelNames
    ChatGenerationParamsReasoningEffort:
      type: string
      enum:
        - xhigh
        - high
        - medium
        - low
        - minimal
        - none
      description: Constrains effort on reasoning for reasoning models
      title: ChatGenerationParamsReasoningEffort
    ReasoningSummaryVerbosity:
      type: string
      enum:
        - auto
        - concise
        - detailed
      title: ReasoningSummaryVerbosity
    ChatGenerationParamsReasoningSummary:
      oneOf:
        - $ref: '#/components/schemas/ReasoningSummaryVerbosity'
        - description: Any type
        - description: Any type
      title: ChatGenerationParamsReasoningSummary
    ChatGenerationParamsReasoning:
      type: object
      properties:
        effort:
          oneOf:
            - $ref: '#/components/schemas/ChatGenerationParamsReasoningEffort'
            - type: 'null'
          description: Constrains effort on reasoning for reasoning models
        summary:
          $ref: '#/components/schemas/ChatGenerationParamsReasoningSummary'
      description: Configuration options for reasoning models
      title: ChatGenerationParamsReasoning
    ResponseFormatTextType:
      type: string
      enum:
        - text
      title: ResponseFormatTextType
    ResponseFormatText:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponseFormatTextType'
      required:
        - type
      description: Default text response format
      title: ResponseFormatText
    ResponseFormatJsonObjectType:
      type: string
      enum:
        - json_object
      title: ResponseFormatJsonObjectType
    ResponseFormatJSONObject:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponseFormatJsonObjectType'
      required:
        - type
      description: JSON object response format
      title: ResponseFormatJSONObject
    ResponseFormatJsonSchemaType:
      type: string
      enum:
        - json_schema
      title: ResponseFormatJsonSchemaType
    JSONSchemaConfig:
      type: object
      properties:
        name:
          type: string
          description: Schema name (a-z, A-Z, 0-9, underscores, dashes, max 64 chars)
        description:
          type: string
          description: Schema description for the model
        schema:
          type: object
          additionalProperties:
            description: Any type
          description: JSON Schema object
        strict:
          type:
            - boolean
            - 'null'
          description: Enable strict schema adherence
      required:
        - name
      description: JSON Schema configuration object
      title: JSONSchemaConfig
    ResponseFormatJSONSchema:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponseFormatJsonSchemaType'
        json_schema:
          $ref: '#/components/schemas/JSONSchemaConfig'
      required:
        - type
        - json_schema
      description: JSON Schema response format for structured outputs
      title: ResponseFormatJSONSchema
    ResponseFormatTextGrammarType:
      type: string
      enum:
        - grammar
      title: ResponseFormatTextGrammarType
    ResponseFormatTextGrammar:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponseFormatTextGrammarType'
        grammar:
          type: string
          description: Custom grammar for text generation
      required:
        - type
        - grammar
      description: Custom grammar response format
      title: ResponseFormatTextGrammar
    ResponseFormatTextPythonType:
      type: string
      enum:
        - python
      title: ResponseFormatTextPythonType
    ResponseFormatTextPython:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponseFormatTextPythonType'
      required:
        - type
      description: Python code response format
      title: ResponseFormatTextPython
    ChatGenerationParamsResponseFormat:
      oneOf:
        - $ref: '#/components/schemas/ResponseFormatText'
        - $ref: '#/components/schemas/ResponseFormatJSONObject'
        - $ref: '#/components/schemas/ResponseFormatJSONSchema'
        - $ref: '#/components/schemas/ResponseFormatTextGrammar'
        - $ref: '#/components/schemas/ResponseFormatTextPython'
      description: Response format configuration
      title: ChatGenerationParamsResponseFormat
    ChatGenerationParamsStop:
      oneOf:
        - type: string
        - type: array
          items:
            type: string
        - description: Any type
      description: Stop sequences (up to 4)
      title: ChatGenerationParamsStop
    ChatStreamOptions:
      type: object
      properties:
        include_usage:
          type: boolean
          description: >-
            Deprecated: This field has no effect. Full usage details are always
            included.
      description: Streaming configuration options
      title: ChatStreamOptions
    ToolChoiceOption0:
      type: string
      enum:
        - none
      title: ToolChoiceOption0
    ToolChoiceOption1:
      type: string
      enum:
        - auto
      title: ToolChoiceOption1
    ToolChoiceOption2:
      type: string
      enum:
        - required
      title: ToolChoiceOption2
    NamedToolChoiceType:
      type: string
      enum:
        - function
      title: NamedToolChoiceType
    NamedToolChoiceFunction:
      type: object
      properties:
        name:
          type: string
          description: Function name to call
      required:
        - name
      title: NamedToolChoiceFunction
    NamedToolChoice:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/NamedToolChoiceType'
        function:
          $ref: '#/components/schemas/NamedToolChoiceFunction'
      required:
        - type
        - function
      description: Named tool choice for specific function
      title: NamedToolChoice
    ToolChoiceOption:
      oneOf:
        - $ref: '#/components/schemas/ToolChoiceOption0'
        - $ref: '#/components/schemas/ToolChoiceOption1'
        - $ref: '#/components/schemas/ToolChoiceOption2'
        - $ref: '#/components/schemas/NamedToolChoice'
      description: Tool choice configuration
      title: ToolChoiceOption
    ToolDefinitionJsonType:
      type: string
      enum:
        - function
      title: ToolDefinitionJsonType
    ToolDefinitionJsonFunction:
      type: object
      properties:
        name:
          type: string
          description: Function name (a-z, A-Z, 0-9, underscores, dashes, max 64 chars)
        description:
          type: string
          description: Function description for the model
        parameters:
          type: object
          additionalProperties:
            description: Any type
          description: Function parameters as JSON Schema object
        strict:
          type:
            - boolean
            - 'null'
          description: Enable strict schema adherence
      required:
        - name
      description: Function definition for tool calling
      title: ToolDefinitionJsonFunction
    ToolDefinitionJson:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ToolDefinitionJsonType'
        function:
          $ref: '#/components/schemas/ToolDefinitionJsonFunction'
          description: Function definition for tool calling
        cache_control:
          $ref: '#/components/schemas/ChatMessageContentItemCacheControl'
      required:
        - type
        - function
      description: Tool definition for function calling
      title: ToolDefinitionJson
    DebugOptions:
      type: object
      properties:
        echo_upstream_body:
          type: boolean
          description: >-
            If true, includes the transformed upstream request body in a debug
            chunk at the start of the stream. Only works with streaming mode.
      description: Debug options for inspecting request transformations (streaming only)
      title: DebugOptions
    ChatGenerationParamsImageConfig:
      oneOf:
        - type: string
        - type: number
          format: double
        - type: array
          items:
            description: Any type
      title: ChatGenerationParamsImageConfig
    ChatGenerationParamsModalitiesItems:
      type: string
      enum:
        - text
        - image
        - audio
      title: ChatGenerationParamsModalitiesItems
    ChatGenerationParams:
      type: object
      properties:
        provider:
          oneOf:
            - $ref: '#/components/schemas/ChatGenerationParamsProvider'
            - type: 'null'
          description: >-
            When multiple model providers are available, optionally indicate
            your routing preference.
        plugins:
          type: array
          items:
            $ref: '#/components/schemas/ChatGenerationParamsPluginsItems'
          description: >-
            Plugins you want to enable for this request, including their
            settings.
        user:
          type: string
          description: Unique user identifier
        session_id:
          type: string
          description: >-
            A unique identifier for grouping related requests (e.g., a
            conversation or agent workflow) for observability. If provided in
            both the request body and the x-session-id header, the body value
            takes precedence. Maximum of 128 characters.
        trace:
          $ref: '#/components/schemas/ChatGenerationParamsTrace'
          description: >-
            Metadata for observability and tracing. Known keys (trace_id,
            trace_name, span_name, generation_name, parent_span_id) have special
            handling. Additional keys are passed through as custom metadata to
            configured broadcast destinations.
        messages:
          type: array
          items:
            $ref: '#/components/schemas/Message'
          description: List of messages for the conversation
        model:
          $ref: '#/components/schemas/ModelName'
        models:
          $ref: '#/components/schemas/ModelNames'
        frequency_penalty:
          type:
            - number
            - 'null'
          format: double
          description: Frequency penalty (-2.0 to 2.0)
        logit_bias:
          type:
            - object
            - 'null'
          additionalProperties:
            type: number
            format: double
          description: Token logit bias adjustments
        logprobs:
          type:
            - boolean
            - 'null'
          description: Return log probabilities
        top_logprobs:
          type:
            - number
            - 'null'
          format: double
          description: Number of top log probabilities to return (0-20)
        max_completion_tokens:
          type:
            - number
            - 'null'
          format: double
          description: Maximum tokens in completion
        max_tokens:
          type:
            - number
            - 'null'
          format: double
          description: >-
            Maximum tokens (deprecated, use max_completion_tokens). Note: some
            providers enforce a minimum of 16.
        metadata:
          type: object
          additionalProperties:
            type: string
          description: >-
            Key-value pairs for additional object information (max 16 pairs, 64
            char keys, 512 char values)
        presence_penalty:
          type:
            - number
            - 'null'
          format: double
          description: Presence penalty (-2.0 to 2.0)
        reasoning:
          $ref: '#/components/schemas/ChatGenerationParamsReasoning'
          description: Configuration options for reasoning models
        response_format:
          $ref: '#/components/schemas/ChatGenerationParamsResponseFormat'
          description: Response format configuration
        seed:
          type:
            - integer
            - 'null'
          description: Random seed for deterministic outputs
        stop:
          $ref: '#/components/schemas/ChatGenerationParamsStop'
          description: Stop sequences (up to 4)
        stream:
          type: boolean
          default: false
          description: Enable streaming response
        stream_options:
          $ref: '#/components/schemas/ChatStreamOptions'
        temperature:
          type:
            - number
            - 'null'
          format: double
          default: 1
          description: Sampling temperature (0-2)
        parallel_tool_calls:
          type:
            - boolean
            - 'null'
        tool_choice:
          $ref: '#/components/schemas/ToolChoiceOption'
        tools:
          type: array
          items:
            $ref: '#/components/schemas/ToolDefinitionJson'
          description: Available tools for function calling
        top_p:
          type:
            - number
            - 'null'
          format: double
          default: 1
          description: Nucleus sampling parameter (0-1)
        debug:
          $ref: '#/components/schemas/DebugOptions'
        image_config:
          type: object
          additionalProperties:
            $ref: '#/components/schemas/ChatGenerationParamsImageConfig'
          description: >-
            Provider-specific image configuration options. Keys and values vary
            by model/provider. See
            https://openrouter.ai/docs/guides/overview/multimodal/image-generation
            for more details.
        modalities:
          type: array
          items:
            $ref: '#/components/schemas/ChatGenerationParamsModalitiesItems'
          description: >-
            Output modalities for the response. Supported values are "text",
            "image", and "audio".
      required:
        - messages
      description: Chat completion request parameters
      title: ChatGenerationParams
    ChatCompletionFinishReason:
      type: string
      enum:
        - tool_calls
        - stop
        - length
        - content_filter
        - error
      title: ChatCompletionFinishReason
    ChatResponseChoiceFinishReason:
      oneOf:
        - $ref: '#/components/schemas/ChatCompletionFinishReason'
        - description: Any type
        - description: Any type
      title: ChatResponseChoiceFinishReason
    ChatMessageTokenLogprobTopLogprobsItems:
      type: object
      properties:
        token:
          type: string
        logprob:
          type: number
          format: double
        bytes:
          type:
            - array
            - 'null'
          items:
            type: number
            format: double
      required:
        - token
        - logprob
        - bytes
      title: ChatMessageTokenLogprobTopLogprobsItems
    ChatMessageTokenLogprob:
      type: object
      properties:
        token:
          type: string
          description: The token
        logprob:
          type: number
          format: double
          description: Log probability of the token
        bytes:
          type:
            - array
            - 'null'
          items:
            type: number
            format: double
          description: UTF-8 bytes of the token
        top_logprobs:
          type: array
          items:
            $ref: '#/components/schemas/ChatMessageTokenLogprobTopLogprobsItems'
          description: Top alternative tokens with probabilities
      required:
        - token
        - logprob
        - bytes
        - top_logprobs
      description: Token log probability information
      title: ChatMessageTokenLogprob
    ChatMessageTokenLogprobs:
      type: object
      properties:
        content:
          type:
            - array
            - 'null'
          items:
            $ref: '#/components/schemas/ChatMessageTokenLogprob'
          description: Log probabilities for content tokens
        refusal:
          type:
            - array
            - 'null'
          items:
            $ref: '#/components/schemas/ChatMessageTokenLogprob'
          description: Log probabilities for refusal tokens
      required:
        - content
      description: Log probabilities for the completion
      title: ChatMessageTokenLogprobs
    ChatResponseChoice:
      type: object
      properties:
        finish_reason:
          $ref: '#/components/schemas/ChatResponseChoiceFinishReason'
        index:
          type: number
          format: double
          description: Choice index
        message:
          $ref: '#/components/schemas/AssistantMessage'
        logprobs:
          $ref: '#/components/schemas/ChatMessageTokenLogprobs'
      required:
        - finish_reason
        - index
        - message
      description: Chat completion choice
      title: ChatResponseChoice
    ChatResponseObject:
      type: string
      enum:
        - chat.completion
      title: ChatResponseObject
    ChatGenerationTokenUsageCompletionTokensDetails:
      type: object
      properties:
        reasoning_tokens:
          type:
            - number
            - 'null'
          format: double
          description: Tokens used for reasoning
        audio_tokens:
          type:
            - number
            - 'null'
          format: double
          description: Tokens used for audio output
        accepted_prediction_tokens:
          type:
            - number
            - 'null'
          format: double
          description: Accepted prediction tokens
        rejected_prediction_tokens:
          type:
            - number
            - 'null'
          format: double
          description: Rejected prediction tokens
      description: Detailed completion token usage
      title: ChatGenerationTokenUsageCompletionTokensDetails
    ChatGenerationTokenUsagePromptTokensDetails:
      type: object
      properties:
        cached_tokens:
          type: number
          format: double
          description: Cached prompt tokens
        cache_write_tokens:
          type: number
          format: double
          description: >-
            Tokens written to cache. Only returned for models with explicit
            caching and cache write pricing.
        audio_tokens:
          type: number
          format: double
          description: Audio input tokens
        video_tokens:
          type: number
          format: double
          description: Video input tokens
      description: Detailed prompt token usage
      title: ChatGenerationTokenUsagePromptTokensDetails
    ChatGenerationTokenUsage:
      type: object
      properties:
        completion_tokens:
          type: number
          format: double
          description: Number of tokens in the completion
        prompt_tokens:
          type: number
          format: double
          description: Number of tokens in the prompt
        total_tokens:
          type: number
          format: double
          description: Total number of tokens
        completion_tokens_details:
          oneOf:
            - $ref: >-
                #/components/schemas/ChatGenerationTokenUsageCompletionTokensDetails
            - type: 'null'
          description: Detailed completion token usage
        prompt_tokens_details:
          oneOf:
            - $ref: '#/components/schemas/ChatGenerationTokenUsagePromptTokensDetails'
            - type: 'null'
          description: Detailed prompt token usage
      required:
        - completion_tokens
        - prompt_tokens
        - total_tokens
      description: Token usage statistics
      title: ChatGenerationTokenUsage
    ChatResponse:
      type: object
      properties:
        id:
          type: string
          description: Unique completion identifier
        choices:
          type: array
          items:
            $ref: '#/components/schemas/ChatResponseChoice'
          description: List of completion choices
        created:
          type: number
          format: double
          description: Unix timestamp of creation
        model:
          type: string
          description: Model used for completion
        object:
          $ref: '#/components/schemas/ChatResponseObject'
        system_fingerprint:
          type:
            - string
            - 'null'
          description: System fingerprint
        usage:
          $ref: '#/components/schemas/ChatGenerationTokenUsage'
      required:
        - id
        - choices
        - created
        - model
        - object
        - system_fingerprint
      description: Chat completion response
      title: ChatResponse
    BadRequestResponseErrorData:
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
      description: Error data for BadRequestResponse
      title: BadRequestResponseErrorData
    BadRequestResponse:
      type: object
      properties:
        error:
          $ref: '#/components/schemas/BadRequestResponseErrorData'
        user_id:
          type:
            - string
            - 'null'
      required:
        - error
      description: Bad Request - Invalid request parameters or malformed input
      title: BadRequestResponse
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
    RequestTimeoutResponseErrorData:
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
      description: Error data for RequestTimeoutResponse
      title: RequestTimeoutResponseErrorData
    RequestTimeoutResponse:
      type: object
      properties:
        error:
          $ref: '#/components/schemas/RequestTimeoutResponseErrorData'
        user_id:
          type:
            - string
            - 'null'
      required:
        - error
      description: Request Timeout - Operation exceeded time limit
      title: RequestTimeoutResponse
    PayloadTooLargeResponseErrorData:
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
      description: Error data for PayloadTooLargeResponse
      title: PayloadTooLargeResponseErrorData
    PayloadTooLargeResponse:
      type: object
      properties:
        error:
          $ref: '#/components/schemas/PayloadTooLargeResponseErrorData'
        user_id:
          type:
            - string
            - 'null'
      required:
        - error
      description: Payload Too Large - Request payload exceeds size limits
      title: PayloadTooLargeResponse
    UnprocessableEntityResponseErrorData:
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
      description: Error data for UnprocessableEntityResponse
      title: UnprocessableEntityResponseErrorData
    UnprocessableEntityResponse:
      type: object
      properties:
        error:
          $ref: '#/components/schemas/UnprocessableEntityResponseErrorData'
        user_id:
          type:
            - string
            - 'null'
      required:
        - error
      description: Unprocessable Entity - Semantic validation failure
      title: UnprocessableEntityResponse
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
    ServiceUnavailableResponseErrorData:
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
      description: Error data for ServiceUnavailableResponse
      title: ServiceUnavailableResponseErrorData
    ServiceUnavailableResponse:
      type: object
      properties:
        error:
          $ref: '#/components/schemas/ServiceUnavailableResponseErrorData'
        user_id:
          type:
            - string
            - 'null'
      required:
        - error
      description: Service Unavailable - Service temporarily unavailable
      title: ServiceUnavailableResponse
  securitySchemes:
    apiKey:
      type: http
      scheme: bearer
      description: API key as bearer token in Authorization header

```

## SDK Code Examples

```python
import requests

url = "https://openrouter.ai/api/v1/chat/completions"

payload = {
    "messages": [
        {
            "role": "system",
            "content": "You are a helpful assistant."
        },
        {
            "role": "user",
            "content": "What is the capital of France?"
        }
    ],
    "model": "openai/gpt-4",
    "max_tokens": 150,
    "temperature": 0.7
}
headers = {
    "Authorization": "Bearer <token>",
    "Content-Type": "application/json"
}

response = requests.post(url, json=payload, headers=headers)

print(response.json())
```

```javascript
const url = 'https://openrouter.ai/api/v1/chat/completions';
const options = {
  method: 'POST',
  headers: {Authorization: 'Bearer <token>', 'Content-Type': 'application/json'},
  body: '{"messages":[{"role":"system","content":"You are a helpful assistant."},{"role":"user","content":"What is the capital of France?"}],"model":"openai/gpt-4","max_tokens":150,"temperature":0.7}'
};

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
	"strings"
	"net/http"
	"io"
)

func main() {

	url := "https://openrouter.ai/api/v1/chat/completions"

	payload := strings.NewReader("{\n  \"messages\": [\n    {\n      \"role\": \"system\",\n      \"content\": \"You are a helpful assistant.\"\n    },\n    {\n      \"role\": \"user\",\n      \"content\": \"What is the capital of France?\"\n    }\n  ],\n  \"model\": \"openai/gpt-4\",\n  \"max_tokens\": 150,\n  \"temperature\": 0.7\n}")

	req, _ := http.NewRequest("POST", url, payload)

	req.Header.Add("Authorization", "Bearer <token>")
	req.Header.Add("Content-Type", "application/json")

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

url = URI("https://openrouter.ai/api/v1/chat/completions")

http = Net::HTTP.new(url.host, url.port)
http.use_ssl = true

request = Net::HTTP::Post.new(url)
request["Authorization"] = 'Bearer <token>'
request["Content-Type"] = 'application/json'
request.body = "{\n  \"messages\": [\n    {\n      \"role\": \"system\",\n      \"content\": \"You are a helpful assistant.\"\n    },\n    {\n      \"role\": \"user\",\n      \"content\": \"What is the capital of France?\"\n    }\n  ],\n  \"model\": \"openai/gpt-4\",\n  \"max_tokens\": 150,\n  \"temperature\": 0.7\n}"

response = http.request(request)
puts response.read_body
```

```java
import com.mashape.unirest.http.HttpResponse;
import com.mashape.unirest.http.Unirest;

HttpResponse<String> response = Unirest.post("https://openrouter.ai/api/v1/chat/completions")
  .header("Authorization", "Bearer <token>")
  .header("Content-Type", "application/json")
  .body("{\n  \"messages\": [\n    {\n      \"role\": \"system\",\n      \"content\": \"You are a helpful assistant.\"\n    },\n    {\n      \"role\": \"user\",\n      \"content\": \"What is the capital of France?\"\n    }\n  ],\n  \"model\": \"openai/gpt-4\",\n  \"max_tokens\": 150,\n  \"temperature\": 0.7\n}")
  .asString();
```

```php
<?php
require_once('vendor/autoload.php');

$client = new \GuzzleHttp\Client();

$response = $client->request('POST', 'https://openrouter.ai/api/v1/chat/completions', [
  'body' => '{
  "messages": [
    {
      "role": "system",
      "content": "You are a helpful assistant."
    },
    {
      "role": "user",
      "content": "What is the capital of France?"
    }
  ],
  "model": "openai/gpt-4",
  "max_tokens": 150,
  "temperature": 0.7
}',
  'headers' => [
    'Authorization' => 'Bearer <token>',
    'Content-Type' => 'application/json',
  ],
]);

echo $response->getBody();
```

```csharp
using RestSharp;

var client = new RestClient("https://openrouter.ai/api/v1/chat/completions");
var request = new RestRequest(Method.POST);
request.AddHeader("Authorization", "Bearer <token>");
request.AddHeader("Content-Type", "application/json");
request.AddParameter("application/json", "{\n  \"messages\": [\n    {\n      \"role\": \"system\",\n      \"content\": \"You are a helpful assistant.\"\n    },\n    {\n      \"role\": \"user\",\n      \"content\": \"What is the capital of France?\"\n    }\n  ],\n  \"model\": \"openai/gpt-4\",\n  \"max_tokens\": 150,\n  \"temperature\": 0.7\n}", ParameterType.RequestBody);
IRestResponse response = client.Execute(request);
```

```swift
import Foundation

let headers = [
  "Authorization": "Bearer <token>",
  "Content-Type": "application/json"
]
let parameters = [
  "messages": [
    [
      "role": "system",
      "content": "You are a helpful assistant."
    ],
    [
      "role": "user",
      "content": "What is the capital of France?"
    ]
  ],
  "model": "openai/gpt-4",
  "max_tokens": 150,
  "temperature": 0.7
] as [String : Any]

let postData = JSONSerialization.data(withJSONObject: parameters, options: [])

let request = NSMutableURLRequest(url: NSURL(string: "https://openrouter.ai/api/v1/chat/completions")! as URL,
                                        cachePolicy: .useProtocolCachePolicy,
                                    timeoutInterval: 10.0)
request.httpMethod = "POST"
request.allHTTPHeaderFields = headers
request.httpBody = postData as Data

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