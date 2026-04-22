# Create a response

POST https://openrouter.ai/api/v1/responses
Content-Type: application/json

Creates a streaming or non-streaming response using OpenResponses API format

Reference: https://openrouter.ai/docs/api/api-reference/responses/create-responses

## OpenAPI Specification

```yaml
openapi: 3.1.0
info:
  title: OpenRouter API
  version: 1.0.0
paths:
  /responses:
    post:
      operationId: create-responses
      summary: Create a response
      description: >-
        Creates a streaming or non-streaming response using OpenResponses API
        format
      tags:
        - subpackage_betaResponses
      parameters:
        - name: Authorization
          in: header
          description: API key as bearer token in Authorization header
          required: true
          schema:
            type: string
      responses:
        '200':
          description: Successful response
          content:
            application/json:
              schema:
                $ref: '#/components/schemas/OpenResponsesNonStreamingResponse'
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
              $ref: '#/components/schemas/OpenResponsesRequest'
servers:
  - url: https://openrouter.ai/api/v1
components:
  schemas:
    OutputItemReasoningType:
      type: string
      enum:
        - reasoning
      title: OutputItemReasoningType
    ReasoningTextContentType:
      type: string
      enum:
        - reasoning_text
      title: ReasoningTextContentType
    ReasoningTextContent:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ReasoningTextContentType'
        text:
          type: string
      required:
        - type
        - text
      title: ReasoningTextContent
    ReasoningSummaryTextType:
      type: string
      enum:
        - summary_text
      title: ReasoningSummaryTextType
    ReasoningSummaryText:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ReasoningSummaryTextType'
        text:
          type: string
      required:
        - type
        - text
      title: ReasoningSummaryText
    OutputItemReasoningStatus0:
      type: string
      enum:
        - completed
      title: OutputItemReasoningStatus0
    OutputItemReasoningStatus1:
      type: string
      enum:
        - incomplete
      title: OutputItemReasoningStatus1
    OutputItemReasoningStatus2:
      type: string
      enum:
        - in_progress
      title: OutputItemReasoningStatus2
    OutputItemReasoningStatus:
      oneOf:
        - $ref: '#/components/schemas/OutputItemReasoningStatus0'
        - $ref: '#/components/schemas/OutputItemReasoningStatus1'
        - $ref: '#/components/schemas/OutputItemReasoningStatus2'
      title: OutputItemReasoningStatus
    OpenResponsesReasoningFormat:
      type: string
      enum:
        - unknown
        - openai-responses-v1
        - azure-openai-responses-v1
        - xai-responses-v1
        - anthropic-claude-v1
        - google-gemini-v1
      title: OpenResponsesReasoningFormat
    OpenResponsesReasoning:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemReasoningType'
        id:
          type: string
        content:
          type:
            - array
            - 'null'
          items:
            $ref: '#/components/schemas/ReasoningTextContent'
        summary:
          type: array
          items:
            $ref: '#/components/schemas/ReasoningSummaryText'
        encrypted_content:
          type:
            - string
            - 'null'
        status:
          $ref: '#/components/schemas/OutputItemReasoningStatus'
        signature:
          type:
            - string
            - 'null'
        format:
          oneOf:
            - $ref: '#/components/schemas/OpenResponsesReasoningFormat'
            - type: 'null'
      required:
        - type
        - id
        - summary
      description: Reasoning output item with signature and format extensions
      title: OpenResponsesReasoning
    OpenResponsesEasyInputMessageType:
      type: string
      enum:
        - message
      title: OpenResponsesEasyInputMessageType
    OpenResponsesEasyInputMessageRole0:
      type: string
      enum:
        - user
      title: OpenResponsesEasyInputMessageRole0
    OpenResponsesEasyInputMessageRole1:
      type: string
      enum:
        - system
      title: OpenResponsesEasyInputMessageRole1
    OpenResponsesEasyInputMessageRole2:
      type: string
      enum:
        - assistant
      title: OpenResponsesEasyInputMessageRole2
    OpenResponsesEasyInputMessageRole3:
      type: string
      enum:
        - developer
      title: OpenResponsesEasyInputMessageRole3
    OpenResponsesEasyInputMessageRole:
      oneOf:
        - $ref: '#/components/schemas/OpenResponsesEasyInputMessageRole0'
        - $ref: '#/components/schemas/OpenResponsesEasyInputMessageRole1'
        - $ref: '#/components/schemas/OpenResponsesEasyInputMessageRole2'
        - $ref: '#/components/schemas/OpenResponsesEasyInputMessageRole3'
      title: OpenResponsesEasyInputMessageRole
    ResponseInputTextType:
      type: string
      enum:
        - input_text
      title: ResponseInputTextType
    ResponseInputText:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponseInputTextType'
        text:
          type: string
      required:
        - type
        - text
      description: Text input content item
      title: ResponseInputText
    ResponseInputImageType:
      type: string
      enum:
        - input_image
      title: ResponseInputImageType
    ResponseInputImageDetail:
      type: string
      enum:
        - auto
        - high
        - low
      title: ResponseInputImageDetail
    OpenResponsesEasyInputMessageContentOneOf0Items1:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponseInputImageType'
        detail:
          $ref: '#/components/schemas/ResponseInputImageDetail'
        image_url:
          type:
            - string
            - 'null'
      required:
        - type
        - detail
      description: Image input content item
      title: OpenResponsesEasyInputMessageContentOneOf0Items1
    ResponseInputFileType:
      type: string
      enum:
        - input_file
      title: ResponseInputFileType
    ResponseInputFile:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponseInputFileType'
        file_id:
          type:
            - string
            - 'null'
        file_data:
          type: string
        filename:
          type: string
        file_url:
          type: string
      required:
        - type
      description: File input content item
      title: ResponseInputFile
    ResponseInputAudioType:
      type: string
      enum:
        - input_audio
      title: ResponseInputAudioType
    ResponseInputAudioInputAudioFormat:
      type: string
      enum:
        - mp3
        - wav
      title: ResponseInputAudioInputAudioFormat
    ResponseInputAudioInputAudio:
      type: object
      properties:
        data:
          type: string
        format:
          $ref: '#/components/schemas/ResponseInputAudioInputAudioFormat'
      required:
        - data
        - format
      title: ResponseInputAudioInputAudio
    ResponseInputAudio:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponseInputAudioType'
        input_audio:
          $ref: '#/components/schemas/ResponseInputAudioInputAudio'
      required:
        - type
        - input_audio
      description: Audio input content item
      title: ResponseInputAudio
    ResponseInputVideoType:
      type: string
      enum:
        - input_video
      title: ResponseInputVideoType
    ResponseInputVideo:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponseInputVideoType'
        video_url:
          type: string
          description: A base64 data URL or remote URL that resolves to a video file
      required:
        - type
        - video_url
      description: Video input content item
      title: ResponseInputVideo
    OpenResponsesEasyInputMessageContentOneOf0Items:
      oneOf:
        - $ref: '#/components/schemas/ResponseInputText'
        - $ref: >-
            #/components/schemas/OpenResponsesEasyInputMessageContentOneOf0Items1
        - $ref: '#/components/schemas/ResponseInputFile'
        - $ref: '#/components/schemas/ResponseInputAudio'
        - $ref: '#/components/schemas/ResponseInputVideo'
      title: OpenResponsesEasyInputMessageContentOneOf0Items
    OpenResponsesEasyInputMessageContent0:
      type: array
      items:
        $ref: '#/components/schemas/OpenResponsesEasyInputMessageContentOneOf0Items'
      title: OpenResponsesEasyInputMessageContent0
    OpenResponsesEasyInputMessageContent:
      oneOf:
        - $ref: '#/components/schemas/OpenResponsesEasyInputMessageContent0'
        - type: string
        - description: Any type
      title: OpenResponsesEasyInputMessageContent
    OpenResponsesEasyInputMessagePhase0:
      type: string
      enum:
        - commentary
      title: OpenResponsesEasyInputMessagePhase0
    OpenResponsesEasyInputMessagePhase1:
      type: string
      enum:
        - final_answer
      title: OpenResponsesEasyInputMessagePhase1
    OpenResponsesEasyInputMessagePhase:
      oneOf:
        - $ref: '#/components/schemas/OpenResponsesEasyInputMessagePhase0'
        - $ref: '#/components/schemas/OpenResponsesEasyInputMessagePhase1'
        - description: Any type
      description: >-
        The phase of an assistant message. Use `commentary` for an intermediate
        assistant message and `final_answer` for the final assistant message.
        For follow-up requests with models like `gpt-5.3-codex` and later,
        preserve and resend phase on all assistant messages. Omitting it can
        degrade performance. Not used for user messages.
      title: OpenResponsesEasyInputMessagePhase
    OpenResponsesEasyInputMessage:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesEasyInputMessageType'
        role:
          $ref: '#/components/schemas/OpenResponsesEasyInputMessageRole'
        content:
          $ref: '#/components/schemas/OpenResponsesEasyInputMessageContent'
        phase:
          $ref: '#/components/schemas/OpenResponsesEasyInputMessagePhase'
          description: >-
            The phase of an assistant message. Use `commentary` for an
            intermediate assistant message and `final_answer` for the final
            assistant message. For follow-up requests with models like
            `gpt-5.3-codex` and later, preserve and resend phase on all
            assistant messages. Omitting it can degrade performance. Not used
            for user messages.
      required:
        - role
      title: OpenResponsesEasyInputMessage
    OpenResponsesInputMessageItemType:
      type: string
      enum:
        - message
      title: OpenResponsesInputMessageItemType
    OpenResponsesInputMessageItemRole0:
      type: string
      enum:
        - user
      title: OpenResponsesInputMessageItemRole0
    OpenResponsesInputMessageItemRole1:
      type: string
      enum:
        - system
      title: OpenResponsesInputMessageItemRole1
    OpenResponsesInputMessageItemRole2:
      type: string
      enum:
        - developer
      title: OpenResponsesInputMessageItemRole2
    OpenResponsesInputMessageItemRole:
      oneOf:
        - $ref: '#/components/schemas/OpenResponsesInputMessageItemRole0'
        - $ref: '#/components/schemas/OpenResponsesInputMessageItemRole1'
        - $ref: '#/components/schemas/OpenResponsesInputMessageItemRole2'
      title: OpenResponsesInputMessageItemRole
    OpenResponsesInputMessageItemContentItems1:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponseInputImageType'
        detail:
          $ref: '#/components/schemas/ResponseInputImageDetail'
        image_url:
          type:
            - string
            - 'null'
      required:
        - type
        - detail
      description: Image input content item
      title: OpenResponsesInputMessageItemContentItems1
    OpenResponsesInputMessageItemContentItems:
      oneOf:
        - $ref: '#/components/schemas/ResponseInputText'
        - $ref: '#/components/schemas/OpenResponsesInputMessageItemContentItems1'
        - $ref: '#/components/schemas/ResponseInputFile'
        - $ref: '#/components/schemas/ResponseInputAudio'
        - $ref: '#/components/schemas/ResponseInputVideo'
      title: OpenResponsesInputMessageItemContentItems
    OpenResponsesInputMessageItem:
      type: object
      properties:
        id:
          type: string
        type:
          $ref: '#/components/schemas/OpenResponsesInputMessageItemType'
        role:
          $ref: '#/components/schemas/OpenResponsesInputMessageItemRole'
        content:
          type:
            - array
            - 'null'
          items:
            $ref: '#/components/schemas/OpenResponsesInputMessageItemContentItems'
      required:
        - role
      title: OpenResponsesInputMessageItem
    OpenResponsesFunctionToolCallType:
      type: string
      enum:
        - function_call
      title: OpenResponsesFunctionToolCallType
    ToolCallStatus:
      type: string
      enum:
        - in_progress
        - completed
        - incomplete
      title: ToolCallStatus
    OpenResponsesFunctionToolCall:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesFunctionToolCallType'
        call_id:
          type: string
        name:
          type: string
        arguments:
          type: string
        id:
          type: string
        status:
          $ref: '#/components/schemas/ToolCallStatus'
      required:
        - type
        - call_id
        - name
        - arguments
        - id
      description: A function call initiated by the model
      title: OpenResponsesFunctionToolCall
    OpenResponsesFunctionCallOutputType:
      type: string
      enum:
        - function_call_output
      title: OpenResponsesFunctionCallOutputType
    OpenResponsesFunctionCallOutput:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesFunctionCallOutputType'
        id:
          type:
            - string
            - 'null'
        call_id:
          type: string
        output:
          type: string
        status:
          $ref: '#/components/schemas/ToolCallStatus'
      required:
        - type
        - call_id
        - output
      description: The output from a function call execution
      title: OpenResponsesFunctionCallOutput
    OutputMessageRole:
      type: string
      enum:
        - assistant
      title: OutputMessageRole
    OutputMessageType:
      type: string
      enum:
        - message
      title: OutputMessageType
    OutputMessageStatus0:
      type: string
      enum:
        - completed
      title: OutputMessageStatus0
    OutputMessageStatus1:
      type: string
      enum:
        - incomplete
      title: OutputMessageStatus1
    OutputMessageStatus2:
      type: string
      enum:
        - in_progress
      title: OutputMessageStatus2
    OutputMessageStatus:
      oneOf:
        - $ref: '#/components/schemas/OutputMessageStatus0'
        - $ref: '#/components/schemas/OutputMessageStatus1'
        - $ref: '#/components/schemas/OutputMessageStatus2'
      title: OutputMessageStatus
    ResponseOutputTextType:
      type: string
      enum:
        - output_text
      title: ResponseOutputTextType
    FileCitationType:
      type: string
      enum:
        - file_citation
      title: FileCitationType
    FileCitation:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/FileCitationType'
        file_id:
          type: string
        filename:
          type: string
        index:
          type: number
          format: double
      required:
        - type
        - file_id
        - filename
        - index
      title: FileCitation
    UrlCitationType:
      type: string
      enum:
        - url_citation
      title: UrlCitationType
    URLCitation:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/UrlCitationType'
        url:
          type: string
        title:
          type: string
        start_index:
          type: number
          format: double
        end_index:
          type: number
          format: double
      required:
        - type
        - url
        - title
        - start_index
        - end_index
      title: URLCitation
    FilePathType:
      type: string
      enum:
        - file_path
      title: FilePathType
    FilePath:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/FilePathType'
        file_id:
          type: string
        index:
          type: number
          format: double
      required:
        - type
        - file_id
        - index
      title: FilePath
    OpenAIResponsesAnnotation:
      oneOf:
        - $ref: '#/components/schemas/FileCitation'
        - $ref: '#/components/schemas/URLCitation'
        - $ref: '#/components/schemas/FilePath'
      title: OpenAIResponsesAnnotation
    ResponseOutputTextLogprobsItemsTopLogprobsItems:
      type: object
      properties:
        token:
          type: string
        bytes:
          type: array
          items:
            type: number
            format: double
        logprob:
          type: number
          format: double
      required:
        - token
        - bytes
        - logprob
      title: ResponseOutputTextLogprobsItemsTopLogprobsItems
    ResponseOutputTextLogprobsItems:
      type: object
      properties:
        token:
          type: string
        bytes:
          type: array
          items:
            type: number
            format: double
        logprob:
          type: number
          format: double
        top_logprobs:
          type: array
          items:
            $ref: >-
              #/components/schemas/ResponseOutputTextLogprobsItemsTopLogprobsItems
      required:
        - token
        - bytes
        - logprob
        - top_logprobs
      title: ResponseOutputTextLogprobsItems
    ResponseOutputText:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponseOutputTextType'
        text:
          type: string
        annotations:
          type: array
          items:
            $ref: '#/components/schemas/OpenAIResponsesAnnotation'
        logprobs:
          type: array
          items:
            $ref: '#/components/schemas/ResponseOutputTextLogprobsItems'
      required:
        - type
        - text
      title: ResponseOutputText
    OpenAiResponsesRefusalContentType:
      type: string
      enum:
        - refusal
      title: OpenAiResponsesRefusalContentType
    OpenAIResponsesRefusalContent:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenAiResponsesRefusalContentType'
        refusal:
          type: string
      required:
        - type
        - refusal
      title: OpenAIResponsesRefusalContent
    OutputMessageContentItems:
      oneOf:
        - $ref: '#/components/schemas/ResponseOutputText'
        - $ref: '#/components/schemas/OpenAIResponsesRefusalContent'
      title: OutputMessageContentItems
    OutputMessagePhase0:
      type: string
      enum:
        - commentary
      title: OutputMessagePhase0
    OutputMessagePhase1:
      type: string
      enum:
        - final_answer
      title: OutputMessagePhase1
    OutputMessagePhase:
      oneOf:
        - $ref: '#/components/schemas/OutputMessagePhase0'
        - $ref: '#/components/schemas/OutputMessagePhase1'
        - description: Any type
      description: >-
        The phase of an assistant message. Use `commentary` for an intermediate
        assistant message and `final_answer` for the final assistant message.
        For follow-up requests with models like `gpt-5.3-codex` and later,
        preserve and resend phase on all assistant messages. Omitting it can
        degrade performance. Not used for user messages.
      title: OutputMessagePhase
    OpenResponsesInputOneOf1ItemsOneOf5ContentOneOf0Items:
      oneOf:
        - $ref: '#/components/schemas/ResponseOutputText'
        - $ref: '#/components/schemas/OpenAIResponsesRefusalContent'
      title: OpenResponsesInputOneOf1ItemsOneOf5ContentOneOf0Items
    OpenResponsesInputOneOf1ItemsOneOf5Content0:
      type: array
      items:
        $ref: >-
          #/components/schemas/OpenResponsesInputOneOf1ItemsOneOf5ContentOneOf0Items
      title: OpenResponsesInputOneOf1ItemsOneOf5Content0
    OpenResponsesInputOneOf1ItemsOneOf5Content:
      oneOf:
        - $ref: '#/components/schemas/OpenResponsesInputOneOf1ItemsOneOf5Content0'
        - type: string
        - description: Any type
      title: OpenResponsesInputOneOf1ItemsOneOf5Content
    OpenResponsesInputOneOf1Items5:
      type: object
      properties:
        id:
          type: string
        role:
          $ref: '#/components/schemas/OutputMessageRole'
        type:
          $ref: '#/components/schemas/OutputMessageType'
        status:
          $ref: '#/components/schemas/OutputMessageStatus'
        content:
          $ref: '#/components/schemas/OpenResponsesInputOneOf1ItemsOneOf5Content'
        phase:
          $ref: '#/components/schemas/OutputMessagePhase'
          description: >-
            The phase of an assistant message. Use `commentary` for an
            intermediate assistant message and `final_answer` for the final
            assistant message. For follow-up requests with models like
            `gpt-5.3-codex` and later, preserve and resend phase on all
            assistant messages. Omitting it can degrade performance. Not used
            for user messages.
      required:
        - id
        - role
        - type
        - content
      description: An output message item
      title: OpenResponsesInputOneOf1Items5
    ResponsesOutputItemReasoningFormat:
      type: string
      enum:
        - unknown
        - openai-responses-v1
        - azure-openai-responses-v1
        - xai-responses-v1
        - anthropic-claude-v1
        - google-gemini-v1
      description: The format of the reasoning content
      title: ResponsesOutputItemReasoningFormat
    OpenResponsesInputOneOf1Items6:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemReasoningType'
        id:
          type: string
        content:
          type:
            - array
            - 'null'
          items:
            $ref: '#/components/schemas/ReasoningTextContent'
        summary:
          type:
            - array
            - 'null'
          items:
            $ref: '#/components/schemas/ReasoningSummaryText'
        encrypted_content:
          type:
            - string
            - 'null'
        status:
          $ref: '#/components/schemas/OutputItemReasoningStatus'
        signature:
          type:
            - string
            - 'null'
          description: A signature for the reasoning content, used for verification
        format:
          oneOf:
            - $ref: '#/components/schemas/ResponsesOutputItemReasoningFormat'
            - type: 'null'
          description: The format of the reasoning content
      required:
        - type
        - id
        - summary
      description: An output item containing reasoning
      title: OpenResponsesInputOneOf1Items6
    OutputItemFunctionCallType:
      type: string
      enum:
        - function_call
      title: OutputItemFunctionCallType
    OutputItemFunctionCallStatus0:
      type: string
      enum:
        - completed
      title: OutputItemFunctionCallStatus0
    OutputItemFunctionCallStatus1:
      type: string
      enum:
        - incomplete
      title: OutputItemFunctionCallStatus1
    OutputItemFunctionCallStatus2:
      type: string
      enum:
        - in_progress
      title: OutputItemFunctionCallStatus2
    OutputItemFunctionCallStatus:
      oneOf:
        - $ref: '#/components/schemas/OutputItemFunctionCallStatus0'
        - $ref: '#/components/schemas/OutputItemFunctionCallStatus1'
        - $ref: '#/components/schemas/OutputItemFunctionCallStatus2'
      title: OutputItemFunctionCallStatus
    ResponsesOutputItemFunctionCall:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemFunctionCallType'
        id:
          type: string
        name:
          type: string
        arguments:
          type: string
        call_id:
          type: string
        status:
          $ref: '#/components/schemas/OutputItemFunctionCallStatus'
      required:
        - type
        - name
        - arguments
        - call_id
      title: ResponsesOutputItemFunctionCall
    OutputItemWebSearchCallType:
      type: string
      enum:
        - web_search_call
      title: OutputItemWebSearchCallType
    OutputItemWebSearchCallActionOneOf0Type:
      type: string
      enum:
        - search
      title: OutputItemWebSearchCallActionOneOf0Type
    OutputItemWebSearchCallActionOneOf0SourcesItemsType:
      type: string
      enum:
        - url
      title: OutputItemWebSearchCallActionOneOf0SourcesItemsType
    OutputItemWebSearchCallActionOneOf0SourcesItems:
      type: object
      properties:
        type:
          $ref: >-
            #/components/schemas/OutputItemWebSearchCallActionOneOf0SourcesItemsType
        url:
          type: string
      required:
        - type
        - url
      title: OutputItemWebSearchCallActionOneOf0SourcesItems
    OutputItemWebSearchCallAction0:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemWebSearchCallActionOneOf0Type'
        query:
          type: string
        queries:
          type: array
          items:
            type: string
        sources:
          type: array
          items:
            $ref: >-
              #/components/schemas/OutputItemWebSearchCallActionOneOf0SourcesItems
      required:
        - type
        - query
      title: OutputItemWebSearchCallAction0
    OutputItemWebSearchCallActionOneOf1Type:
      type: string
      enum:
        - open_page
      title: OutputItemWebSearchCallActionOneOf1Type
    OutputItemWebSearchCallAction1:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemWebSearchCallActionOneOf1Type'
        url:
          type:
            - string
            - 'null'
      required:
        - type
      title: OutputItemWebSearchCallAction1
    OutputItemWebSearchCallActionOneOf2Type:
      type: string
      enum:
        - find_in_page
      title: OutputItemWebSearchCallActionOneOf2Type
    OutputItemWebSearchCallAction2:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemWebSearchCallActionOneOf2Type'
        pattern:
          type: string
        url:
          type: string
      required:
        - type
        - pattern
        - url
      title: OutputItemWebSearchCallAction2
    OutputItemWebSearchCallAction:
      oneOf:
        - $ref: '#/components/schemas/OutputItemWebSearchCallAction0'
        - $ref: '#/components/schemas/OutputItemWebSearchCallAction1'
        - $ref: '#/components/schemas/OutputItemWebSearchCallAction2'
      title: OutputItemWebSearchCallAction
    WebSearchStatus:
      type: string
      enum:
        - completed
        - searching
        - in_progress
        - failed
      title: WebSearchStatus
    ResponsesWebSearchCallOutput:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemWebSearchCallType'
        id:
          type: string
        action:
          $ref: '#/components/schemas/OutputItemWebSearchCallAction'
        status:
          $ref: '#/components/schemas/WebSearchStatus'
      required:
        - type
        - id
        - action
        - status
      title: ResponsesWebSearchCallOutput
    OutputItemFileSearchCallType:
      type: string
      enum:
        - file_search_call
      title: OutputItemFileSearchCallType
    ResponsesOutputItemFileSearchCall:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemFileSearchCallType'
        id:
          type: string
        queries:
          type: array
          items:
            type: string
        status:
          $ref: '#/components/schemas/WebSearchStatus'
      required:
        - type
        - id
        - queries
        - status
      title: ResponsesOutputItemFileSearchCall
    OutputItemImageGenerationCallType:
      type: string
      enum:
        - image_generation_call
      title: OutputItemImageGenerationCallType
    ImageGenerationStatus:
      type: string
      enum:
        - in_progress
        - completed
        - generating
        - failed
      title: ImageGenerationStatus
    ResponsesImageGenerationCall:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemImageGenerationCallType'
        id:
          type: string
        result:
          type:
            - string
            - 'null'
        status:
          $ref: '#/components/schemas/ImageGenerationStatus'
      required:
        - type
        - id
        - status
      title: ResponsesImageGenerationCall
    OpenResponsesInputOneOf1Items:
      oneOf:
        - $ref: '#/components/schemas/OpenResponsesReasoning'
        - $ref: '#/components/schemas/OpenResponsesEasyInputMessage'
        - $ref: '#/components/schemas/OpenResponsesInputMessageItem'
        - $ref: '#/components/schemas/OpenResponsesFunctionToolCall'
        - $ref: '#/components/schemas/OpenResponsesFunctionCallOutput'
        - $ref: '#/components/schemas/OpenResponsesInputOneOf1Items5'
        - $ref: '#/components/schemas/OpenResponsesInputOneOf1Items6'
        - $ref: '#/components/schemas/ResponsesOutputItemFunctionCall'
        - $ref: '#/components/schemas/ResponsesWebSearchCallOutput'
        - $ref: '#/components/schemas/ResponsesOutputItemFileSearchCall'
        - $ref: '#/components/schemas/ResponsesImageGenerationCall'
      title: OpenResponsesInputOneOf1Items
    OpenResponsesInput1:
      type: array
      items:
        $ref: '#/components/schemas/OpenResponsesInputOneOf1Items'
      title: OpenResponsesInput1
    OpenResponsesInput:
      oneOf:
        - type: string
        - $ref: '#/components/schemas/OpenResponsesInput1'
      description: Input for a response request - can be a string or array of items
      title: OpenResponsesInput
    OpenResponsesRequestMetadata:
      type: object
      additionalProperties:
        type: string
      description: >-
        Metadata key-value pairs for the request. Keys must be ≤64 characters
        and cannot contain brackets. Values must be ≤512 characters. Maximum 16
        pairs allowed.
      title: OpenResponsesRequestMetadata
    OpenResponsesFunctionToolType:
      type: string
      enum:
        - function
      title: OpenResponsesFunctionToolType
    OpenResponsesRequestToolsItems0:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesFunctionToolType'
        name:
          type: string
        description:
          type:
            - string
            - 'null'
        strict:
          type:
            - boolean
            - 'null'
        parameters:
          type:
            - object
            - 'null'
          additionalProperties:
            description: Any type
      required:
        - type
        - name
        - parameters
      description: Function tool definition
      title: OpenResponsesRequestToolsItems0
    OpenResponsesWebSearchPreviewToolType:
      type: string
      enum:
        - web_search_preview
      title: OpenResponsesWebSearchPreviewToolType
    ResponsesSearchContextSize:
      type: string
      enum:
        - low
        - medium
        - high
      description: Size of the search context for web search tools
      title: ResponsesSearchContextSize
    WebSearchPreviewToolUserLocationType:
      type: string
      enum:
        - approximate
      title: WebSearchPreviewToolUserLocationType
    WebSearchPreviewToolUserLocation:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/WebSearchPreviewToolUserLocationType'
        city:
          type:
            - string
            - 'null'
        country:
          type:
            - string
            - 'null'
        region:
          type:
            - string
            - 'null'
        timezone:
          type:
            - string
            - 'null'
      required:
        - type
      title: WebSearchPreviewToolUserLocation
    OpenResponsesWebSearchPreviewTool:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesWebSearchPreviewToolType'
        search_context_size:
          $ref: '#/components/schemas/ResponsesSearchContextSize'
        user_location:
          $ref: '#/components/schemas/WebSearchPreviewToolUserLocation'
      required:
        - type
      description: Web search preview tool configuration
      title: OpenResponsesWebSearchPreviewTool
    OpenResponsesWebSearchPreview20250311ToolType:
      type: string
      enum:
        - web_search_preview_2025_03_11
      title: OpenResponsesWebSearchPreview20250311ToolType
    OpenResponsesWebSearchPreview20250311Tool:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesWebSearchPreview20250311ToolType'
        search_context_size:
          $ref: '#/components/schemas/ResponsesSearchContextSize'
        user_location:
          $ref: '#/components/schemas/WebSearchPreviewToolUserLocation'
      required:
        - type
      description: Web search preview tool configuration (2025-03-11 version)
      title: OpenResponsesWebSearchPreview20250311Tool
    OpenResponsesWebSearchToolType:
      type: string
      enum:
        - web_search
      title: OpenResponsesWebSearchToolType
    OpenResponsesWebSearchToolFilters:
      type: object
      properties:
        allowed_domains:
          type:
            - array
            - 'null'
          items:
            type: string
      title: OpenResponsesWebSearchToolFilters
    ResponsesWebSearchUserLocationType:
      type: string
      enum:
        - approximate
      title: ResponsesWebSearchUserLocationType
    ResponsesWebSearchUserLocation:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponsesWebSearchUserLocationType'
        city:
          type:
            - string
            - 'null'
        country:
          type:
            - string
            - 'null'
        region:
          type:
            - string
            - 'null'
        timezone:
          type:
            - string
            - 'null'
      description: User location information for web search
      title: ResponsesWebSearchUserLocation
    OpenResponsesWebSearchTool:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesWebSearchToolType'
        filters:
          oneOf:
            - $ref: '#/components/schemas/OpenResponsesWebSearchToolFilters'
            - type: 'null'
        search_context_size:
          $ref: '#/components/schemas/ResponsesSearchContextSize'
        user_location:
          $ref: '#/components/schemas/ResponsesWebSearchUserLocation'
      required:
        - type
      description: Web search tool configuration
      title: OpenResponsesWebSearchTool
    OpenResponsesWebSearch20250826ToolType:
      type: string
      enum:
        - web_search_2025_08_26
      title: OpenResponsesWebSearch20250826ToolType
    OpenResponsesWebSearch20250826ToolFilters:
      type: object
      properties:
        allowed_domains:
          type:
            - array
            - 'null'
          items:
            type: string
      title: OpenResponsesWebSearch20250826ToolFilters
    OpenResponsesWebSearch20250826Tool:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesWebSearch20250826ToolType'
        filters:
          oneOf:
            - $ref: '#/components/schemas/OpenResponsesWebSearch20250826ToolFilters'
            - type: 'null'
        search_context_size:
          $ref: '#/components/schemas/ResponsesSearchContextSize'
        user_location:
          $ref: '#/components/schemas/ResponsesWebSearchUserLocation'
      required:
        - type
      description: Web search tool configuration (2025-08-26 version)
      title: OpenResponsesWebSearch20250826Tool
    OpenResponsesFileSearchToolType:
      type: string
      enum:
        - file_search
      title: OpenResponsesFileSearchToolType
    OpenResponsesFileSearchToolFiltersOneOf0Type:
      type: string
      enum:
        - eq
        - ne
        - gt
        - gte
        - lt
        - lte
      title: OpenResponsesFileSearchToolFiltersOneOf0Type
    OpenResponsesFileSearchToolFiltersOneOf0ValueOneOf3Items:
      oneOf:
        - type: string
        - type: number
          format: double
      title: OpenResponsesFileSearchToolFiltersOneOf0ValueOneOf3Items
    OpenResponsesFileSearchToolFiltersOneOf0Value3:
      type: array
      items:
        $ref: >-
          #/components/schemas/OpenResponsesFileSearchToolFiltersOneOf0ValueOneOf3Items
      title: OpenResponsesFileSearchToolFiltersOneOf0Value3
    OpenResponsesFileSearchToolFiltersOneOf0Value:
      oneOf:
        - type: string
        - type: number
          format: double
        - type: boolean
        - $ref: '#/components/schemas/OpenResponsesFileSearchToolFiltersOneOf0Value3'
      title: OpenResponsesFileSearchToolFiltersOneOf0Value
    OpenResponsesFileSearchToolFilters0:
      type: object
      properties:
        key:
          type: string
        type:
          $ref: '#/components/schemas/OpenResponsesFileSearchToolFiltersOneOf0Type'
        value:
          $ref: '#/components/schemas/OpenResponsesFileSearchToolFiltersOneOf0Value'
      required:
        - key
        - type
        - value
      title: OpenResponsesFileSearchToolFilters0
    CompoundFilterType:
      type: string
      enum:
        - and
        - or
      title: CompoundFilterType
    CompoundFilter:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/CompoundFilterType'
        filters:
          type: array
          items:
            type: object
            additionalProperties:
              description: Any type
      required:
        - type
        - filters
      description: A compound filter that combines multiple comparison or compound filters
      title: CompoundFilter
    OpenResponsesFileSearchToolFilters:
      oneOf:
        - $ref: '#/components/schemas/OpenResponsesFileSearchToolFilters0'
        - $ref: '#/components/schemas/CompoundFilter'
        - description: Any type
      title: OpenResponsesFileSearchToolFilters
    OpenResponsesFileSearchToolRankingOptionsRanker:
      type: string
      enum:
        - auto
        - default-2024-11-15
      title: OpenResponsesFileSearchToolRankingOptionsRanker
    OpenResponsesFileSearchToolRankingOptions:
      type: object
      properties:
        ranker:
          $ref: '#/components/schemas/OpenResponsesFileSearchToolRankingOptionsRanker'
        score_threshold:
          type: number
          format: double
      title: OpenResponsesFileSearchToolRankingOptions
    OpenResponsesFileSearchTool:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesFileSearchToolType'
        vector_store_ids:
          type: array
          items:
            type: string
        filters:
          $ref: '#/components/schemas/OpenResponsesFileSearchToolFilters'
        max_num_results:
          type: integer
        ranking_options:
          $ref: '#/components/schemas/OpenResponsesFileSearchToolRankingOptions'
      required:
        - type
        - vector_store_ids
      description: File search tool configuration
      title: OpenResponsesFileSearchTool
    OpenResponsesComputerToolType:
      type: string
      enum:
        - computer_use_preview
      title: OpenResponsesComputerToolType
    OpenResponsesComputerToolEnvironment:
      type: string
      enum:
        - windows
        - mac
        - linux
        - ubuntu
        - browser
      title: OpenResponsesComputerToolEnvironment
    OpenResponsesComputerTool:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesComputerToolType'
        display_height:
          type: number
          format: double
        display_width:
          type: number
          format: double
        environment:
          $ref: '#/components/schemas/OpenResponsesComputerToolEnvironment'
      required:
        - type
        - display_height
        - display_width
        - environment
      description: Computer use preview tool configuration
      title: OpenResponsesComputerTool
    OpenResponsesCodeInterpreterToolType:
      type: string
      enum:
        - code_interpreter
      title: OpenResponsesCodeInterpreterToolType
    OpenResponsesCodeInterpreterToolContainerOneOf1Type:
      type: string
      enum:
        - auto
      title: OpenResponsesCodeInterpreterToolContainerOneOf1Type
    OpenResponsesCodeInterpreterToolContainerOneOf1MemoryLimit:
      type: string
      enum:
        - 1g
        - 4g
        - 16g
        - 64g
      title: OpenResponsesCodeInterpreterToolContainerOneOf1MemoryLimit
    OpenResponsesCodeInterpreterToolContainer1:
      type: object
      properties:
        type:
          $ref: >-
            #/components/schemas/OpenResponsesCodeInterpreterToolContainerOneOf1Type
        file_ids:
          type: array
          items:
            type: string
        memory_limit:
          oneOf:
            - $ref: >-
                #/components/schemas/OpenResponsesCodeInterpreterToolContainerOneOf1MemoryLimit
            - type: 'null'
      required:
        - type
      title: OpenResponsesCodeInterpreterToolContainer1
    OpenResponsesCodeInterpreterToolContainer:
      oneOf:
        - type: string
        - $ref: '#/components/schemas/OpenResponsesCodeInterpreterToolContainer1'
      title: OpenResponsesCodeInterpreterToolContainer
    OpenResponsesCodeInterpreterTool:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesCodeInterpreterToolType'
        container:
          $ref: '#/components/schemas/OpenResponsesCodeInterpreterToolContainer'
      required:
        - type
        - container
      description: Code interpreter tool configuration
      title: OpenResponsesCodeInterpreterTool
    OpenResponsesMcpToolType:
      type: string
      enum:
        - mcp
      title: OpenResponsesMcpToolType
    OpenResponsesMcpToolAllowedTools1:
      type: object
      properties:
        tool_names:
          type: array
          items:
            type: string
        read_only:
          type: boolean
      title: OpenResponsesMcpToolAllowedTools1
    OpenResponsesMcpToolAllowedTools:
      oneOf:
        - type: array
          items:
            type: string
        - $ref: '#/components/schemas/OpenResponsesMcpToolAllowedTools1'
        - description: Any type
        - description: Any type
      title: OpenResponsesMcpToolAllowedTools
    OpenResponsesMcpToolConnectorId:
      type: string
      enum:
        - connector_dropbox
        - connector_gmail
        - connector_googlecalendar
        - connector_googledrive
        - connector_microsoftteams
        - connector_outlookcalendar
        - connector_outlookemail
        - connector_sharepoint
      title: OpenResponsesMcpToolConnectorId
    OpenResponsesMcpToolRequireApprovalOneOf0Never:
      type: object
      properties:
        tool_names:
          type: array
          items:
            type: string
      title: OpenResponsesMcpToolRequireApprovalOneOf0Never
    OpenResponsesMcpToolRequireApprovalOneOf0Always:
      type: object
      properties:
        tool_names:
          type: array
          items:
            type: string
      title: OpenResponsesMcpToolRequireApprovalOneOf0Always
    OpenResponsesMcpToolRequireApproval0:
      type: object
      properties:
        never:
          $ref: '#/components/schemas/OpenResponsesMcpToolRequireApprovalOneOf0Never'
        always:
          $ref: '#/components/schemas/OpenResponsesMcpToolRequireApprovalOneOf0Always'
      title: OpenResponsesMcpToolRequireApproval0
    OpenResponsesMcpToolRequireApproval1:
      type: string
      enum:
        - always
      title: OpenResponsesMcpToolRequireApproval1
    OpenResponsesMcpToolRequireApproval2:
      type: string
      enum:
        - never
      title: OpenResponsesMcpToolRequireApproval2
    OpenResponsesMcpToolRequireApproval:
      oneOf:
        - $ref: '#/components/schemas/OpenResponsesMcpToolRequireApproval0'
        - $ref: '#/components/schemas/OpenResponsesMcpToolRequireApproval1'
        - $ref: '#/components/schemas/OpenResponsesMcpToolRequireApproval2'
        - description: Any type
        - description: Any type
      title: OpenResponsesMcpToolRequireApproval
    OpenResponsesMcpTool:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesMcpToolType'
        server_label:
          type: string
        allowed_tools:
          $ref: '#/components/schemas/OpenResponsesMcpToolAllowedTools'
        authorization:
          type: string
        connector_id:
          $ref: '#/components/schemas/OpenResponsesMcpToolConnectorId'
        headers:
          type:
            - object
            - 'null'
          additionalProperties:
            type: string
        require_approval:
          $ref: '#/components/schemas/OpenResponsesMcpToolRequireApproval'
        server_description:
          type: string
        server_url:
          type: string
      required:
        - type
        - server_label
      description: MCP (Model Context Protocol) tool configuration
      title: OpenResponsesMcpTool
    OpenResponsesImageGenerationToolType:
      type: string
      enum:
        - image_generation
      title: OpenResponsesImageGenerationToolType
    OpenResponsesImageGenerationToolBackground:
      type: string
      enum:
        - transparent
        - opaque
        - auto
      title: OpenResponsesImageGenerationToolBackground
    OpenResponsesImageGenerationToolInputFidelity:
      type: string
      enum:
        - high
        - low
      title: OpenResponsesImageGenerationToolInputFidelity
    OpenResponsesImageGenerationToolInputImageMask:
      type: object
      properties:
        image_url:
          type: string
        file_id:
          type: string
      title: OpenResponsesImageGenerationToolInputImageMask
    OpenResponsesImageGenerationToolModel:
      type: string
      enum:
        - gpt-image-1
        - gpt-image-1-mini
      title: OpenResponsesImageGenerationToolModel
    OpenResponsesImageGenerationToolModeration:
      type: string
      enum:
        - auto
        - low
      title: OpenResponsesImageGenerationToolModeration
    OpenResponsesImageGenerationToolOutputFormat:
      type: string
      enum:
        - png
        - webp
        - jpeg
      title: OpenResponsesImageGenerationToolOutputFormat
    OpenResponsesImageGenerationToolQuality:
      type: string
      enum:
        - low
        - medium
        - high
        - auto
      title: OpenResponsesImageGenerationToolQuality
    OpenResponsesImageGenerationToolSize:
      type: string
      enum:
        - 1024x1024
        - 1024x1536
        - 1536x1024
        - auto
      title: OpenResponsesImageGenerationToolSize
    OpenResponsesImageGenerationTool:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesImageGenerationToolType'
        background:
          $ref: '#/components/schemas/OpenResponsesImageGenerationToolBackground'
        input_fidelity:
          oneOf:
            - $ref: >-
                #/components/schemas/OpenResponsesImageGenerationToolInputFidelity
            - type: 'null'
        input_image_mask:
          $ref: '#/components/schemas/OpenResponsesImageGenerationToolInputImageMask'
        model:
          $ref: '#/components/schemas/OpenResponsesImageGenerationToolModel'
        moderation:
          $ref: '#/components/schemas/OpenResponsesImageGenerationToolModeration'
        output_compression:
          type: number
          format: double
        output_format:
          $ref: '#/components/schemas/OpenResponsesImageGenerationToolOutputFormat'
        partial_images:
          type: number
          format: double
        quality:
          $ref: '#/components/schemas/OpenResponsesImageGenerationToolQuality'
        size:
          $ref: '#/components/schemas/OpenResponsesImageGenerationToolSize'
      required:
        - type
      description: Image generation tool configuration
      title: OpenResponsesImageGenerationTool
    OpenResponsesLocalShellToolType:
      type: string
      enum:
        - local_shell
      title: OpenResponsesLocalShellToolType
    OpenResponsesLocalShellTool:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesLocalShellToolType'
      required:
        - type
      description: Local shell tool configuration
      title: OpenResponsesLocalShellTool
    OpenResponsesFunctionShellToolType:
      type: string
      enum:
        - shell
      title: OpenResponsesFunctionShellToolType
    OpenResponsesFunctionShellTool:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesFunctionShellToolType'
      required:
        - type
      description: Shell tool configuration
      title: OpenResponsesFunctionShellTool
    OpenResponsesApplyPatchToolType:
      type: string
      enum:
        - apply_patch
      title: OpenResponsesApplyPatchToolType
    OpenResponsesApplyPatchTool:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesApplyPatchToolType'
      required:
        - type
      description: Apply patch tool configuration
      title: OpenResponsesApplyPatchTool
    OpenResponsesCustomToolType:
      type: string
      enum:
        - custom
      title: OpenResponsesCustomToolType
    OpenResponsesCustomToolFormatOneOf0Type:
      type: string
      enum:
        - text
      title: OpenResponsesCustomToolFormatOneOf0Type
    OpenResponsesCustomToolFormat0:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesCustomToolFormatOneOf0Type'
      required:
        - type
      title: OpenResponsesCustomToolFormat0
    OpenResponsesCustomToolFormatOneOf1Type:
      type: string
      enum:
        - grammar
      title: OpenResponsesCustomToolFormatOneOf1Type
    OpenResponsesCustomToolFormatOneOf1Syntax:
      type: string
      enum:
        - lark
        - regex
      title: OpenResponsesCustomToolFormatOneOf1Syntax
    OpenResponsesCustomToolFormat1:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesCustomToolFormatOneOf1Type'
        definition:
          type: string
        syntax:
          $ref: '#/components/schemas/OpenResponsesCustomToolFormatOneOf1Syntax'
      required:
        - type
        - definition
        - syntax
      title: OpenResponsesCustomToolFormat1
    OpenResponsesCustomToolFormat:
      oneOf:
        - $ref: '#/components/schemas/OpenResponsesCustomToolFormat0'
        - $ref: '#/components/schemas/OpenResponsesCustomToolFormat1'
      title: OpenResponsesCustomToolFormat
    OpenResponsesCustomTool:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesCustomToolType'
        name:
          type: string
        description:
          type: string
        format:
          $ref: '#/components/schemas/OpenResponsesCustomToolFormat'
      required:
        - type
        - name
      description: Custom tool configuration
      title: OpenResponsesCustomTool
    OpenResponsesRequestToolsItems:
      oneOf:
        - $ref: '#/components/schemas/OpenResponsesRequestToolsItems0'
        - $ref: '#/components/schemas/OpenResponsesWebSearchPreviewTool'
        - $ref: '#/components/schemas/OpenResponsesWebSearchPreview20250311Tool'
        - $ref: '#/components/schemas/OpenResponsesWebSearchTool'
        - $ref: '#/components/schemas/OpenResponsesWebSearch20250826Tool'
        - $ref: '#/components/schemas/OpenResponsesFileSearchTool'
        - $ref: '#/components/schemas/OpenResponsesComputerTool'
        - $ref: '#/components/schemas/OpenResponsesCodeInterpreterTool'
        - $ref: '#/components/schemas/OpenResponsesMcpTool'
        - $ref: '#/components/schemas/OpenResponsesImageGenerationTool'
        - $ref: '#/components/schemas/OpenResponsesLocalShellTool'
        - $ref: '#/components/schemas/OpenResponsesFunctionShellTool'
        - $ref: '#/components/schemas/OpenResponsesApplyPatchTool'
        - $ref: '#/components/schemas/OpenResponsesCustomTool'
      title: OpenResponsesRequestToolsItems
    OpenAiResponsesToolChoice0:
      type: string
      enum:
        - auto
      title: OpenAiResponsesToolChoice0
    OpenAiResponsesToolChoice1:
      type: string
      enum:
        - none
      title: OpenAiResponsesToolChoice1
    OpenAiResponsesToolChoice2:
      type: string
      enum:
        - required
      title: OpenAiResponsesToolChoice2
    OpenAiResponsesToolChoiceOneOf3Type:
      type: string
      enum:
        - function
      title: OpenAiResponsesToolChoiceOneOf3Type
    OpenAiResponsesToolChoice3:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenAiResponsesToolChoiceOneOf3Type'
        name:
          type: string
      required:
        - type
        - name
      title: OpenAiResponsesToolChoice3
    OpenAiResponsesToolChoiceOneOf4Type0:
      type: string
      enum:
        - web_search_preview_2025_03_11
      title: OpenAiResponsesToolChoiceOneOf4Type0
    OpenAiResponsesToolChoiceOneOf4Type1:
      type: string
      enum:
        - web_search_preview
      title: OpenAiResponsesToolChoiceOneOf4Type1
    OpenAiResponsesToolChoiceOneOf4Type:
      oneOf:
        - $ref: '#/components/schemas/OpenAiResponsesToolChoiceOneOf4Type0'
        - $ref: '#/components/schemas/OpenAiResponsesToolChoiceOneOf4Type1'
      title: OpenAiResponsesToolChoiceOneOf4Type
    OpenAiResponsesToolChoice4:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenAiResponsesToolChoiceOneOf4Type'
      required:
        - type
      title: OpenAiResponsesToolChoice4
    OpenAIResponsesToolChoice:
      oneOf:
        - $ref: '#/components/schemas/OpenAiResponsesToolChoice0'
        - $ref: '#/components/schemas/OpenAiResponsesToolChoice1'
        - $ref: '#/components/schemas/OpenAiResponsesToolChoice2'
        - $ref: '#/components/schemas/OpenAiResponsesToolChoice3'
        - $ref: '#/components/schemas/OpenAiResponsesToolChoice4'
      title: OpenAIResponsesToolChoice
    ResponsesFormatTextType:
      type: string
      enum:
        - text
      title: ResponsesFormatTextType
    ResponsesFormatText:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponsesFormatTextType'
      required:
        - type
      description: Plain text response format
      title: ResponsesFormatText
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
    ResponsesFormatTextJsonSchemaConfigType:
      type: string
      enum:
        - json_schema
      title: ResponsesFormatTextJsonSchemaConfigType
    ResponsesFormatTextJSONSchemaConfig:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponsesFormatTextJsonSchemaConfigType'
        name:
          type: string
        description:
          type: string
        strict:
          type:
            - boolean
            - 'null'
        schema:
          type: object
          additionalProperties:
            description: Any type
      required:
        - type
        - name
        - schema
      description: JSON schema constrained response format
      title: ResponsesFormatTextJSONSchemaConfig
    ResponseFormatTextConfig:
      oneOf:
        - $ref: '#/components/schemas/ResponsesFormatText'
        - $ref: '#/components/schemas/ResponseFormatJSONObject'
        - $ref: '#/components/schemas/ResponsesFormatTextJSONSchemaConfig'
      description: Text response format configuration
      title: ResponseFormatTextConfig
    ResponseTextConfigVerbosity:
      type: string
      enum:
        - high
        - low
        - medium
      title: ResponseTextConfigVerbosity
    OpenResponsesResponseText:
      type: object
      properties:
        format:
          $ref: '#/components/schemas/ResponseFormatTextConfig'
        verbosity:
          oneOf:
            - $ref: '#/components/schemas/ResponseTextConfigVerbosity'
            - type: 'null'
      description: Text output configuration including format and verbosity
      title: OpenResponsesResponseText
    OpenAIResponsesReasoningEffort:
      type: string
      enum:
        - xhigh
        - high
        - medium
        - low
        - minimal
        - none
      title: OpenAIResponsesReasoningEffort
    ReasoningSummaryVerbosity:
      type: string
      enum:
        - auto
        - concise
        - detailed
      title: ReasoningSummaryVerbosity
    OpenResponsesReasoningConfig:
      type: object
      properties:
        effort:
          $ref: '#/components/schemas/OpenAIResponsesReasoningEffort'
        summary:
          $ref: '#/components/schemas/ReasoningSummaryVerbosity'
        max_tokens:
          type:
            - number
            - 'null'
          format: double
        enabled:
          type:
            - boolean
            - 'null'
      description: Configuration for reasoning mode in the response
      title: OpenResponsesReasoningConfig
    OpenResponsesRequestImageConfig:
      oneOf:
        - type: string
        - type: number
          format: double
      title: OpenResponsesRequestImageConfig
    ResponsesOutputModality:
      type: string
      enum:
        - text
        - image
      title: ResponsesOutputModality
    ResponseInputImage:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/ResponseInputImageType'
        detail:
          $ref: '#/components/schemas/ResponseInputImageDetail'
        image_url:
          type:
            - string
            - 'null'
      required:
        - type
        - detail
      description: Image input content item
      title: ResponseInputImage
    OpenAiResponsesPromptVariables:
      oneOf:
        - type: string
        - $ref: '#/components/schemas/ResponseInputText'
        - $ref: '#/components/schemas/ResponseInputImage'
        - $ref: '#/components/schemas/ResponseInputFile'
      title: OpenAiResponsesPromptVariables
    OpenAIResponsesPrompt:
      type: object
      properties:
        id:
          type: string
        variables:
          type:
            - object
            - 'null'
          additionalProperties:
            $ref: '#/components/schemas/OpenAiResponsesPromptVariables'
      required:
        - id
      title: OpenAIResponsesPrompt
    OpenAIResponsesIncludable:
      type: string
      enum:
        - file_search_call.results
        - message.input_image.image_url
        - computer_call_output.output.image_url
        - reasoning.encrypted_content
        - code_interpreter_call.outputs
      title: OpenAIResponsesIncludable
    OpenResponsesRequestServiceTier:
      type: string
      enum:
        - auto
      default: auto
      title: OpenResponsesRequestServiceTier
    OpenResponsesRequestTruncation:
      type: object
      properties: {}
      title: OpenResponsesRequestTruncation
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
    OpenResponsesRequestProviderOrderItems:
      oneOf:
        - $ref: '#/components/schemas/ProviderName'
        - type: string
      title: OpenResponsesRequestProviderOrderItems
    OpenResponsesRequestProviderOnlyItems:
      oneOf:
        - $ref: '#/components/schemas/ProviderName'
        - type: string
      title: OpenResponsesRequestProviderOnlyItems
    OpenResponsesRequestProviderIgnoreItems:
      oneOf:
        - $ref: '#/components/schemas/ProviderName'
        - type: string
      title: OpenResponsesRequestProviderIgnoreItems
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
    ProviderSort:
      type: string
      enum:
        - price
        - throughput
        - latency
      description: The provider sorting strategy (price, throughput, latency)
      title: ProviderSort
    ProviderSortConfigBy:
      type: string
      enum:
        - price
        - throughput
        - latency
      description: The provider sorting strategy (price, throughput, latency)
      title: ProviderSortConfigBy
    ProviderSortConfigPartition:
      type: string
      enum:
        - model
        - none
      description: >-
        Partitioning strategy for sorting: "model" (default) groups endpoints by
        model before sorting (fallback models remain fallbacks), "none" sorts
        all endpoints together regardless of model.
      title: ProviderSortConfigPartition
    ProviderSortConfig:
      type: object
      properties:
        by:
          oneOf:
            - $ref: '#/components/schemas/ProviderSortConfigBy'
            - type: 'null'
          description: The provider sorting strategy (price, throughput, latency)
        partition:
          oneOf:
            - $ref: '#/components/schemas/ProviderSortConfigPartition'
            - type: 'null'
          description: >-
            Partitioning strategy for sorting: "model" (default) groups
            endpoints by model before sorting (fallback models remain
            fallbacks), "none" sorts all endpoints together regardless of model.
      description: The provider sorting strategy (price, throughput, latency)
      title: ProviderSortConfig
    OpenResponsesRequestProviderSort:
      oneOf:
        - $ref: '#/components/schemas/ProviderSort'
        - $ref: '#/components/schemas/ProviderSortConfig'
        - description: Any type
      description: >-
        The sorting strategy to use for this request, if "order" is not
        specified. When set, no load balancing is performed.
      title: OpenResponsesRequestProviderSort
    BigNumberUnion:
      type: string
      description: Price per million prompt tokens
      title: BigNumberUnion
    OpenResponsesRequestProviderMaxPriceCompletion:
      type: object
      properties: {}
      title: OpenResponsesRequestProviderMaxPriceCompletion
    OpenResponsesRequestProviderMaxPriceImage:
      type: object
      properties: {}
      title: OpenResponsesRequestProviderMaxPriceImage
    OpenResponsesRequestProviderMaxPriceAudio:
      type: object
      properties: {}
      title: OpenResponsesRequestProviderMaxPriceAudio
    OpenResponsesRequestProviderMaxPriceRequest:
      type: object
      properties: {}
      title: OpenResponsesRequestProviderMaxPriceRequest
    OpenResponsesRequestProviderMaxPrice:
      type: object
      properties:
        prompt:
          $ref: '#/components/schemas/BigNumberUnion'
        completion:
          $ref: '#/components/schemas/OpenResponsesRequestProviderMaxPriceCompletion'
        image:
          $ref: '#/components/schemas/OpenResponsesRequestProviderMaxPriceImage'
        audio:
          $ref: '#/components/schemas/OpenResponsesRequestProviderMaxPriceAudio'
        request:
          $ref: '#/components/schemas/OpenResponsesRequestProviderMaxPriceRequest'
      description: >-
        The object specifying the maximum price you want to pay for this
        request. USD price per million tokens, for prompt and completion.
      title: OpenResponsesRequestProviderMaxPrice
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
    OpenResponsesRequestProvider:
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
            $ref: '#/components/schemas/OpenResponsesRequestProviderOrderItems'
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
            $ref: '#/components/schemas/OpenResponsesRequestProviderOnlyItems'
          description: >-
            List of provider slugs to allow. If provided, this list is merged
            with your account-wide allowed provider settings for this request.
        ignore:
          type:
            - array
            - 'null'
          items:
            $ref: '#/components/schemas/OpenResponsesRequestProviderIgnoreItems'
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
          $ref: '#/components/schemas/OpenResponsesRequestProviderSort'
          description: >-
            The sorting strategy to use for this request, if "order" is not
            specified. When set, no load balancing is performed.
        max_price:
          $ref: '#/components/schemas/OpenResponsesRequestProviderMaxPrice'
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
      title: OpenResponsesRequestProvider
    OpenResponsesRequestPluginsItemsOneOf0Id:
      type: string
      enum:
        - auto-router
      title: OpenResponsesRequestPluginsItemsOneOf0Id
    OpenResponsesRequestPluginsItems0:
      type: object
      properties:
        id:
          $ref: '#/components/schemas/OpenResponsesRequestPluginsItemsOneOf0Id'
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
      title: OpenResponsesRequestPluginsItems0
    OpenResponsesRequestPluginsItemsOneOf1Id:
      type: string
      enum:
        - moderation
      title: OpenResponsesRequestPluginsItemsOneOf1Id
    OpenResponsesRequestPluginsItems1:
      type: object
      properties:
        id:
          $ref: '#/components/schemas/OpenResponsesRequestPluginsItemsOneOf1Id'
      required:
        - id
      title: OpenResponsesRequestPluginsItems1
    OpenResponsesRequestPluginsItemsOneOf2Id:
      type: string
      enum:
        - web
      title: OpenResponsesRequestPluginsItemsOneOf2Id
    WebSearchEngine:
      type: string
      enum:
        - native
        - exa
      description: The search engine to use for web search.
      title: WebSearchEngine
    OpenResponsesRequestPluginsItems2:
      type: object
      properties:
        id:
          $ref: '#/components/schemas/OpenResponsesRequestPluginsItemsOneOf2Id'
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
      title: OpenResponsesRequestPluginsItems2
    OpenResponsesRequestPluginsItemsOneOf3Id:
      type: string
      enum:
        - file-parser
      title: OpenResponsesRequestPluginsItemsOneOf3Id
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
    OpenResponsesRequestPluginsItems3:
      type: object
      properties:
        id:
          $ref: '#/components/schemas/OpenResponsesRequestPluginsItemsOneOf3Id'
        enabled:
          type: boolean
          description: >-
            Set to false to disable the file-parser plugin for this request.
            Defaults to true.
        pdf:
          $ref: '#/components/schemas/PDFParserOptions'
      required:
        - id
      title: OpenResponsesRequestPluginsItems3
    OpenResponsesRequestPluginsItemsOneOf4Id:
      type: string
      enum:
        - response-healing
      title: OpenResponsesRequestPluginsItemsOneOf4Id
    OpenResponsesRequestPluginsItems4:
      type: object
      properties:
        id:
          $ref: '#/components/schemas/OpenResponsesRequestPluginsItemsOneOf4Id'
        enabled:
          type: boolean
          description: >-
            Set to false to disable the response-healing plugin for this
            request. Defaults to true.
      required:
        - id
      title: OpenResponsesRequestPluginsItems4
    OpenResponsesRequestPluginsItems:
      oneOf:
        - $ref: '#/components/schemas/OpenResponsesRequestPluginsItems0'
        - $ref: '#/components/schemas/OpenResponsesRequestPluginsItems1'
        - $ref: '#/components/schemas/OpenResponsesRequestPluginsItems2'
        - $ref: '#/components/schemas/OpenResponsesRequestPluginsItems3'
        - $ref: '#/components/schemas/OpenResponsesRequestPluginsItems4'
      title: OpenResponsesRequestPluginsItems
    OpenResponsesRequestTrace:
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
      title: OpenResponsesRequestTrace
    OpenResponsesRequest:
      type: object
      properties:
        input:
          $ref: '#/components/schemas/OpenResponsesInput'
        instructions:
          type:
            - string
            - 'null'
        metadata:
          $ref: '#/components/schemas/OpenResponsesRequestMetadata'
        tools:
          type: array
          items:
            $ref: '#/components/schemas/OpenResponsesRequestToolsItems'
        tool_choice:
          $ref: '#/components/schemas/OpenAIResponsesToolChoice'
        parallel_tool_calls:
          type:
            - boolean
            - 'null'
        model:
          type: string
        models:
          type: array
          items:
            type: string
        text:
          $ref: '#/components/schemas/OpenResponsesResponseText'
        reasoning:
          $ref: '#/components/schemas/OpenResponsesReasoningConfig'
        max_output_tokens:
          type:
            - number
            - 'null'
          format: double
        temperature:
          type:
            - number
            - 'null'
          format: double
        top_p:
          type:
            - number
            - 'null'
          format: double
        top_logprobs:
          type:
            - integer
            - 'null'
        max_tool_calls:
          type:
            - integer
            - 'null'
        presence_penalty:
          type:
            - number
            - 'null'
          format: double
        frequency_penalty:
          type:
            - number
            - 'null'
          format: double
        top_k:
          type: number
          format: double
        image_config:
          type: object
          additionalProperties:
            $ref: '#/components/schemas/OpenResponsesRequestImageConfig'
          description: >-
            Provider-specific image configuration options. Keys and values vary
            by model/provider. See
            https://openrouter.ai/docs/features/multimodal/image-generation for
            more details.
        modalities:
          type: array
          items:
            $ref: '#/components/schemas/ResponsesOutputModality'
          description: >-
            Output modalities for the response. Supported values are "text" and
            "image".
        prompt_cache_key:
          type:
            - string
            - 'null'
        previous_response_id:
          type:
            - string
            - 'null'
        prompt:
          $ref: '#/components/schemas/OpenAIResponsesPrompt'
        include:
          type:
            - array
            - 'null'
          items:
            $ref: '#/components/schemas/OpenAIResponsesIncludable'
        background:
          type:
            - boolean
            - 'null'
        safety_identifier:
          type:
            - string
            - 'null'
        store:
          type: boolean
          enum:
            - false
        service_tier:
          $ref: '#/components/schemas/OpenResponsesRequestServiceTier'
        truncation:
          $ref: '#/components/schemas/OpenResponsesRequestTruncation'
        stream:
          type: boolean
          default: false
        provider:
          oneOf:
            - $ref: '#/components/schemas/OpenResponsesRequestProvider'
            - type: 'null'
          description: >-
            When multiple model providers are available, optionally indicate
            your routing preference.
        plugins:
          type: array
          items:
            $ref: '#/components/schemas/OpenResponsesRequestPluginsItems'
          description: >-
            Plugins you want to enable for this request, including their
            settings.
        user:
          type: string
          description: >-
            A unique identifier representing your end-user, which helps
            distinguish between different users of your app. This allows your
            app to identify specific users in case of abuse reports, preventing
            your entire app from being affected by the actions of individual
            users. Maximum of 128 characters.
        session_id:
          type: string
          description: >-
            A unique identifier for grouping related requests (e.g., a
            conversation or agent workflow) for observability. If provided in
            both the request body and the x-session-id header, the body value
            takes precedence. Maximum of 128 characters.
        trace:
          $ref: '#/components/schemas/OpenResponsesRequestTrace'
          description: >-
            Metadata for observability and tracing. Known keys (trace_id,
            trace_name, span_name, generation_name, parent_span_id) have special
            handling. Additional keys are passed through as custom metadata to
            configured broadcast destinations.
      description: Request schema for Responses endpoint
      title: OpenResponsesRequest
    OpenAiResponsesNonStreamingResponseObject:
      type: string
      enum:
        - response
      title: OpenAiResponsesNonStreamingResponseObject
    OpenAIResponsesResponseStatus:
      type: string
      enum:
        - completed
        - incomplete
        - in_progress
        - failed
        - cancelled
        - queued
      title: OpenAIResponsesResponseStatus
    OutputMessage:
      type: object
      properties:
        id:
          type: string
        role:
          $ref: '#/components/schemas/OutputMessageRole'
        type:
          $ref: '#/components/schemas/OutputMessageType'
        status:
          $ref: '#/components/schemas/OutputMessageStatus'
        content:
          type: array
          items:
            $ref: '#/components/schemas/OutputMessageContentItems'
        phase:
          $ref: '#/components/schemas/OutputMessagePhase'
          description: >-
            The phase of an assistant message. Use `commentary` for an
            intermediate assistant message and `final_answer` for the final
            assistant message. For follow-up requests with models like
            `gpt-5.3-codex` and later, preserve and resend phase on all
            assistant messages. Omitting it can degrade performance. Not used
            for user messages.
      required:
        - id
        - role
        - type
        - content
      title: OutputMessage
    OutputItemReasoning:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemReasoningType'
        id:
          type: string
        content:
          type: array
          items:
            $ref: '#/components/schemas/ReasoningTextContent'
        summary:
          type: array
          items:
            $ref: '#/components/schemas/ReasoningSummaryText'
        encrypted_content:
          type:
            - string
            - 'null'
        status:
          $ref: '#/components/schemas/OutputItemReasoningStatus'
      required:
        - type
        - id
        - summary
      title: OutputItemReasoning
    OutputItemFunctionCall:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemFunctionCallType'
        id:
          type: string
        name:
          type: string
        arguments:
          type: string
        call_id:
          type: string
        status:
          $ref: '#/components/schemas/OutputItemFunctionCallStatus'
      required:
        - type
        - name
        - arguments
        - call_id
      title: OutputItemFunctionCall
    OutputItemWebSearchCall:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemWebSearchCallType'
        id:
          type: string
        action:
          $ref: '#/components/schemas/OutputItemWebSearchCallAction'
        status:
          $ref: '#/components/schemas/WebSearchStatus'
      required:
        - type
        - id
        - action
        - status
      title: OutputItemWebSearchCall
    OutputItemFileSearchCall:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemFileSearchCallType'
        id:
          type: string
        queries:
          type: array
          items:
            type: string
        status:
          $ref: '#/components/schemas/WebSearchStatus'
      required:
        - type
        - id
        - queries
        - status
      title: OutputItemFileSearchCall
    OutputItemImageGenerationCall:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemImageGenerationCallType'
        id:
          type: string
        result:
          type:
            - string
            - 'null'
        status:
          $ref: '#/components/schemas/ImageGenerationStatus'
      required:
        - type
        - id
        - status
      title: OutputItemImageGenerationCall
    OpenAiResponsesNonStreamingResponseOutputItems:
      oneOf:
        - $ref: '#/components/schemas/OutputMessage'
        - $ref: '#/components/schemas/OutputItemReasoning'
        - $ref: '#/components/schemas/OutputItemFunctionCall'
        - $ref: '#/components/schemas/OutputItemWebSearchCall'
        - $ref: '#/components/schemas/OutputItemFileSearchCall'
        - $ref: '#/components/schemas/OutputItemImageGenerationCall'
      title: OpenAiResponsesNonStreamingResponseOutputItems
    ResponsesErrorFieldCode:
      type: string
      enum:
        - server_error
        - rate_limit_exceeded
        - invalid_prompt
        - vector_store_timeout
        - invalid_image
        - invalid_image_format
        - invalid_base64_image
        - invalid_image_url
        - image_too_large
        - image_too_small
        - image_parse_error
        - image_content_policy_violation
        - invalid_image_mode
        - image_file_too_large
        - unsupported_image_media_type
        - empty_image_file
        - failed_to_download_image
        - image_file_not_found
      title: ResponsesErrorFieldCode
    ResponsesErrorField:
      type: object
      properties:
        code:
          $ref: '#/components/schemas/ResponsesErrorFieldCode'
        message:
          type: string
      required:
        - code
        - message
      description: Error information returned from the API
      title: ResponsesErrorField
    OpenAiResponsesIncompleteDetailsReason:
      type: string
      enum:
        - max_output_tokens
        - content_filter
      title: OpenAiResponsesIncompleteDetailsReason
    OpenAIResponsesIncompleteDetails:
      type: object
      properties:
        reason:
          $ref: '#/components/schemas/OpenAiResponsesIncompleteDetailsReason'
      title: OpenAIResponsesIncompleteDetails
    OpenAiResponsesUsageInputTokensDetails:
      type: object
      properties:
        cached_tokens:
          type: number
          format: double
      required:
        - cached_tokens
      title: OpenAiResponsesUsageInputTokensDetails
    OpenAiResponsesUsageOutputTokensDetails:
      type: object
      properties:
        reasoning_tokens:
          type: number
          format: double
      required:
        - reasoning_tokens
      title: OpenAiResponsesUsageOutputTokensDetails
    OpenAIResponsesUsage:
      type: object
      properties:
        input_tokens:
          type: number
          format: double
        input_tokens_details:
          $ref: '#/components/schemas/OpenAiResponsesUsageInputTokensDetails'
        output_tokens:
          type: number
          format: double
        output_tokens_details:
          $ref: '#/components/schemas/OpenAiResponsesUsageOutputTokensDetails'
        total_tokens:
          type: number
          format: double
      required:
        - input_tokens
        - input_tokens_details
        - output_tokens
        - output_tokens_details
        - total_tokens
      title: OpenAIResponsesUsage
    OpenAiResponsesInputOneOf1ItemsOneOf0Type:
      type: string
      enum:
        - message
      title: OpenAiResponsesInputOneOf1ItemsOneOf0Type
    OpenAiResponsesInputOneOf1ItemsOneOf0Role0:
      type: string
      enum:
        - user
      title: OpenAiResponsesInputOneOf1ItemsOneOf0Role0
    OpenAiResponsesInputOneOf1ItemsOneOf0Role1:
      type: string
      enum:
        - system
      title: OpenAiResponsesInputOneOf1ItemsOneOf0Role1
    OpenAiResponsesInputOneOf1ItemsOneOf0Role2:
      type: string
      enum:
        - assistant
      title: OpenAiResponsesInputOneOf1ItemsOneOf0Role2
    OpenAiResponsesInputOneOf1ItemsOneOf0Role3:
      type: string
      enum:
        - developer
      title: OpenAiResponsesInputOneOf1ItemsOneOf0Role3
    OpenAiResponsesInputOneOf1ItemsOneOf0Role:
      oneOf:
        - $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf0Role0'
        - $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf0Role1'
        - $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf0Role2'
        - $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf0Role3'
      title: OpenAiResponsesInputOneOf1ItemsOneOf0Role
    OpenAiResponsesInputOneOf1ItemsOneOf0ContentOneOf0Items:
      oneOf:
        - $ref: '#/components/schemas/ResponseInputText'
        - $ref: '#/components/schemas/ResponseInputImage'
        - $ref: '#/components/schemas/ResponseInputFile'
        - $ref: '#/components/schemas/ResponseInputAudio'
      title: OpenAiResponsesInputOneOf1ItemsOneOf0ContentOneOf0Items
    OpenAiResponsesInputOneOf1ItemsOneOf0Content0:
      type: array
      items:
        $ref: >-
          #/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf0ContentOneOf0Items
      title: OpenAiResponsesInputOneOf1ItemsOneOf0Content0
    OpenAiResponsesInputOneOf1ItemsOneOf0Content:
      oneOf:
        - $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf0Content0'
        - type: string
      title: OpenAiResponsesInputOneOf1ItemsOneOf0Content
    OpenAiResponsesInputOneOf1ItemsOneOf0Phase0:
      type: string
      enum:
        - commentary
      title: OpenAiResponsesInputOneOf1ItemsOneOf0Phase0
    OpenAiResponsesInputOneOf1ItemsOneOf0Phase1:
      type: string
      enum:
        - final_answer
      title: OpenAiResponsesInputOneOf1ItemsOneOf0Phase1
    OpenAiResponsesInputOneOf1ItemsOneOf0Phase:
      oneOf:
        - $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf0Phase0'
        - $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf0Phase1'
        - description: Any type
      title: OpenAiResponsesInputOneOf1ItemsOneOf0Phase
    OpenAiResponsesInputOneOf1Items0:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf0Type'
        role:
          $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf0Role'
        content:
          $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf0Content'
        phase:
          $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf0Phase'
      required:
        - role
        - content
      title: OpenAiResponsesInputOneOf1Items0
    OpenAiResponsesInputOneOf1ItemsOneOf1Type:
      type: string
      enum:
        - message
      title: OpenAiResponsesInputOneOf1ItemsOneOf1Type
    OpenAiResponsesInputOneOf1ItemsOneOf1Role0:
      type: string
      enum:
        - user
      title: OpenAiResponsesInputOneOf1ItemsOneOf1Role0
    OpenAiResponsesInputOneOf1ItemsOneOf1Role1:
      type: string
      enum:
        - system
      title: OpenAiResponsesInputOneOf1ItemsOneOf1Role1
    OpenAiResponsesInputOneOf1ItemsOneOf1Role2:
      type: string
      enum:
        - developer
      title: OpenAiResponsesInputOneOf1ItemsOneOf1Role2
    OpenAiResponsesInputOneOf1ItemsOneOf1Role:
      oneOf:
        - $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf1Role0'
        - $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf1Role1'
        - $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf1Role2'
      title: OpenAiResponsesInputOneOf1ItemsOneOf1Role
    OpenAiResponsesInputOneOf1ItemsOneOf1ContentItems:
      oneOf:
        - $ref: '#/components/schemas/ResponseInputText'
        - $ref: '#/components/schemas/ResponseInputImage'
        - $ref: '#/components/schemas/ResponseInputFile'
        - $ref: '#/components/schemas/ResponseInputAudio'
      title: OpenAiResponsesInputOneOf1ItemsOneOf1ContentItems
    OpenAiResponsesInputOneOf1Items1:
      type: object
      properties:
        id:
          type: string
        type:
          $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf1Type'
        role:
          $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf1Role'
        content:
          type: array
          items:
            $ref: >-
              #/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf1ContentItems
      required:
        - id
        - role
        - content
      title: OpenAiResponsesInputOneOf1Items1
    OpenAiResponsesInputOneOf1ItemsOneOf2Type:
      type: string
      enum:
        - function_call_output
      title: OpenAiResponsesInputOneOf1ItemsOneOf2Type
    OpenAiResponsesInputOneOf1Items2:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf2Type'
        id:
          type:
            - string
            - 'null'
        call_id:
          type: string
        output:
          type: string
        status:
          $ref: '#/components/schemas/ToolCallStatus'
      required:
        - type
        - call_id
        - output
      title: OpenAiResponsesInputOneOf1Items2
    OpenAiResponsesInputOneOf1ItemsOneOf3Type:
      type: string
      enum:
        - function_call
      title: OpenAiResponsesInputOneOf1ItemsOneOf3Type
    OpenAiResponsesInputOneOf1Items3:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenAiResponsesInputOneOf1ItemsOneOf3Type'
        call_id:
          type: string
        name:
          type: string
        arguments:
          type: string
        id:
          type: string
        status:
          $ref: '#/components/schemas/ToolCallStatus'
      required:
        - type
        - call_id
        - name
        - arguments
      title: OpenAiResponsesInputOneOf1Items3
    OpenAiResponsesInputOneOf1Items:
      oneOf:
        - $ref: '#/components/schemas/OpenAiResponsesInputOneOf1Items0'
        - $ref: '#/components/schemas/OpenAiResponsesInputOneOf1Items1'
        - $ref: '#/components/schemas/OpenAiResponsesInputOneOf1Items2'
        - $ref: '#/components/schemas/OpenAiResponsesInputOneOf1Items3'
        - $ref: '#/components/schemas/OutputItemImageGenerationCall'
        - $ref: '#/components/schemas/OutputMessage'
      title: OpenAiResponsesInputOneOf1Items
    OpenAiResponsesInput1:
      type: array
      items:
        $ref: '#/components/schemas/OpenAiResponsesInputOneOf1Items'
      title: OpenAiResponsesInput1
    OpenAIResponsesInput:
      oneOf:
        - type: string
        - $ref: '#/components/schemas/OpenAiResponsesInput1'
        - description: Any type
      title: OpenAIResponsesInput
    OpenAiResponsesNonStreamingResponseToolsItems0:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OpenResponsesFunctionToolType'
        name:
          type: string
        description:
          type:
            - string
            - 'null'
        strict:
          type:
            - boolean
            - 'null'
        parameters:
          type:
            - object
            - 'null'
          additionalProperties:
            description: Any type
      required:
        - type
        - name
        - parameters
      description: Function tool definition
      title: OpenAiResponsesNonStreamingResponseToolsItems0
    OpenAiResponsesNonStreamingResponseToolsItems:
      oneOf:
        - $ref: '#/components/schemas/OpenAiResponsesNonStreamingResponseToolsItems0'
        - $ref: '#/components/schemas/OpenResponsesWebSearchPreviewTool'
        - $ref: '#/components/schemas/OpenResponsesWebSearchPreview20250311Tool'
        - $ref: '#/components/schemas/OpenResponsesWebSearchTool'
        - $ref: '#/components/schemas/OpenResponsesWebSearch20250826Tool'
        - $ref: '#/components/schemas/OpenResponsesFileSearchTool'
        - $ref: '#/components/schemas/OpenResponsesComputerTool'
        - $ref: '#/components/schemas/OpenResponsesCodeInterpreterTool'
        - $ref: '#/components/schemas/OpenResponsesMcpTool'
        - $ref: '#/components/schemas/OpenResponsesImageGenerationTool'
        - $ref: '#/components/schemas/OpenResponsesLocalShellTool'
        - $ref: '#/components/schemas/OpenResponsesFunctionShellTool'
        - $ref: '#/components/schemas/OpenResponsesApplyPatchTool'
        - $ref: '#/components/schemas/OpenResponsesCustomTool'
      title: OpenAiResponsesNonStreamingResponseToolsItems
    OpenAIResponsesReasoningConfig:
      type: object
      properties:
        effort:
          $ref: '#/components/schemas/OpenAIResponsesReasoningEffort'
        summary:
          $ref: '#/components/schemas/ReasoningSummaryVerbosity'
      title: OpenAIResponsesReasoningConfig
    OpenAIResponsesServiceTier:
      type: string
      enum:
        - auto
        - default
        - flex
        - priority
        - scale
      title: OpenAIResponsesServiceTier
    OpenAIResponsesTruncation:
      type: string
      enum:
        - auto
        - disabled
      title: OpenAIResponsesTruncation
    ResponseTextConfig:
      type: object
      properties:
        format:
          $ref: '#/components/schemas/ResponseFormatTextConfig'
        verbosity:
          oneOf:
            - $ref: '#/components/schemas/ResponseTextConfigVerbosity'
            - type: 'null'
      description: Text output configuration including format and verbosity
      title: ResponseTextConfig
    ResponsesOutputMessage:
      type: object
      properties:
        id:
          type: string
        role:
          $ref: '#/components/schemas/OutputMessageRole'
        type:
          $ref: '#/components/schemas/OutputMessageType'
        status:
          $ref: '#/components/schemas/OutputMessageStatus'
        content:
          type: array
          items:
            $ref: '#/components/schemas/OutputMessageContentItems'
        phase:
          $ref: '#/components/schemas/OutputMessagePhase'
          description: >-
            The phase of an assistant message. Use `commentary` for an
            intermediate assistant message and `final_answer` for the final
            assistant message. For follow-up requests with models like
            `gpt-5.3-codex` and later, preserve and resend phase on all
            assistant messages. Omitting it can degrade performance. Not used
            for user messages.
      required:
        - id
        - role
        - type
        - content
      description: An output message item
      title: ResponsesOutputMessage
    ResponsesOutputItemReasoning:
      type: object
      properties:
        type:
          $ref: '#/components/schemas/OutputItemReasoningType'
        id:
          type: string
        content:
          type:
            - array
            - 'null'
          items:
            $ref: '#/components/schemas/ReasoningTextContent'
        summary:
          type: array
          items:
            $ref: '#/components/schemas/ReasoningSummaryText'
        encrypted_content:
          type:
            - string
            - 'null'
        status:
          $ref: '#/components/schemas/OutputItemReasoningStatus'
        signature:
          type:
            - string
            - 'null'
          description: A signature for the reasoning content, used for verification
        format:
          oneOf:
            - $ref: '#/components/schemas/ResponsesOutputItemReasoningFormat'
            - type: 'null'
          description: The format of the reasoning content
      required:
        - type
        - id
        - summary
      description: An output item containing reasoning
      title: ResponsesOutputItemReasoning
    ResponsesOutputItem:
      oneOf:
        - $ref: '#/components/schemas/ResponsesOutputMessage'
        - $ref: '#/components/schemas/ResponsesOutputItemReasoning'
        - $ref: '#/components/schemas/ResponsesOutputItemFunctionCall'
        - $ref: '#/components/schemas/ResponsesWebSearchCallOutput'
        - $ref: '#/components/schemas/ResponsesOutputItemFileSearchCall'
        - $ref: '#/components/schemas/ResponsesImageGenerationCall'
      description: An output item from the response
      title: ResponsesOutputItem
    OpenResponsesUsageCostDetails:
      type: object
      properties:
        upstream_inference_cost:
          type:
            - number
            - 'null'
          format: double
        upstream_inference_input_cost:
          type: number
          format: double
        upstream_inference_output_cost:
          type: number
          format: double
      required:
        - upstream_inference_input_cost
        - upstream_inference_output_cost
      title: OpenResponsesUsageCostDetails
    OpenResponsesUsage:
      type: object
      properties:
        input_tokens:
          type: number
          format: double
        input_tokens_details:
          $ref: '#/components/schemas/OpenAiResponsesUsageInputTokensDetails'
        output_tokens:
          type: number
          format: double
        output_tokens_details:
          $ref: '#/components/schemas/OpenAiResponsesUsageOutputTokensDetails'
        total_tokens:
          type: number
          format: double
        cost:
          type:
            - number
            - 'null'
          format: double
          description: Cost of the completion
        is_byok:
          type: boolean
          description: Whether a request was made using a Bring Your Own Key configuration
        cost_details:
          $ref: '#/components/schemas/OpenResponsesUsageCostDetails'
      required:
        - input_tokens
        - input_tokens_details
        - output_tokens
        - output_tokens_details
        - total_tokens
      description: Token usage information for the response
      title: OpenResponsesUsage
    OpenResponsesNonStreamingResponse:
      type: object
      properties:
        id:
          type: string
        object:
          $ref: '#/components/schemas/OpenAiResponsesNonStreamingResponseObject'
        created_at:
          type: number
          format: double
        model:
          type: string
        status:
          $ref: '#/components/schemas/OpenAIResponsesResponseStatus'
        completed_at:
          type:
            - number
            - 'null'
          format: double
        output:
          type: array
          items:
            $ref: '#/components/schemas/ResponsesOutputItem'
        user:
          type:
            - string
            - 'null'
        output_text:
          type: string
        prompt_cache_key:
          type:
            - string
            - 'null'
        safety_identifier:
          type:
            - string
            - 'null'
        error:
          $ref: '#/components/schemas/ResponsesErrorField'
        incomplete_details:
          $ref: '#/components/schemas/OpenAIResponsesIncompleteDetails'
        usage:
          $ref: '#/components/schemas/OpenResponsesUsage'
        max_tool_calls:
          type:
            - number
            - 'null'
          format: double
        top_logprobs:
          type: number
          format: double
        max_output_tokens:
          type:
            - number
            - 'null'
          format: double
        temperature:
          type:
            - number
            - 'null'
          format: double
        top_p:
          type:
            - number
            - 'null'
          format: double
        presence_penalty:
          type:
            - number
            - 'null'
          format: double
        frequency_penalty:
          type:
            - number
            - 'null'
          format: double
        instructions:
          $ref: '#/components/schemas/OpenAIResponsesInput'
        metadata:
          $ref: '#/components/schemas/OpenResponsesRequestMetadata'
        tools:
          type: array
          items:
            $ref: '#/components/schemas/OpenAiResponsesNonStreamingResponseToolsItems'
        tool_choice:
          $ref: '#/components/schemas/OpenAIResponsesToolChoice'
        parallel_tool_calls:
          type: boolean
        prompt:
          $ref: '#/components/schemas/OpenAIResponsesPrompt'
        background:
          type:
            - boolean
            - 'null'
        previous_response_id:
          type:
            - string
            - 'null'
        reasoning:
          $ref: '#/components/schemas/OpenAIResponsesReasoningConfig'
        service_tier:
          $ref: '#/components/schemas/OpenAIResponsesServiceTier'
        store:
          type: boolean
        truncation:
          $ref: '#/components/schemas/OpenAIResponsesTruncation'
        text:
          $ref: '#/components/schemas/ResponseTextConfig'
      required:
        - id
        - object
        - created_at
        - model
        - status
        - completed_at
        - output
        - error
        - incomplete_details
        - temperature
        - top_p
        - presence_penalty
        - frequency_penalty
        - instructions
        - metadata
        - tools
        - tool_choice
        - parallel_tool_calls
      description: Complete non-streaming response from the Responses API
      title: OpenResponsesNonStreamingResponse
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

url = "https://openrouter.ai/api/v1/responses"

payload = {
    "input": [
        {
            "type": "message",
            "role": "user",
            "content": "Hello, how are you?"
        }
    ],
    "tools": [
        {
            "type": "function",
            "name": "get_current_weather",
            "description": "Get the current weather in a given location",
            "parameters": {
                "type": "object",
                "properties": { "location": { "type": "string" } }
            }
        }
    ],
    "model": "anthropic/claude-4.5-sonnet-20250929",
    "temperature": 0.7,
    "top_p": 0.9
}
headers = {
    "Authorization": "Bearer <token>",
    "Content-Type": "application/json"
}

response = requests.post(url, json=payload, headers=headers)

print(response.json())
```

```javascript
const url = 'https://openrouter.ai/api/v1/responses';
const options = {
  method: 'POST',
  headers: {Authorization: 'Bearer <token>', 'Content-Type': 'application/json'},
  body: '{"input":[{"type":"message","role":"user","content":"Hello, how are you?"}],"tools":[{"type":"function","name":"get_current_weather","description":"Get the current weather in a given location","parameters":{"type":"object","properties":{"location":{"type":"string"}}}}],"model":"anthropic/claude-4.5-sonnet-20250929","temperature":0.7,"top_p":0.9}'
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

	url := "https://openrouter.ai/api/v1/responses"

	payload := strings.NewReader("{\n  \"input\": [\n    {\n      \"type\": \"message\",\n      \"role\": \"user\",\n      \"content\": \"Hello, how are you?\"\n    }\n  ],\n  \"tools\": [\n    {\n      \"type\": \"function\",\n      \"name\": \"get_current_weather\",\n      \"description\": \"Get the current weather in a given location\",\n      \"parameters\": {\n        \"type\": \"object\",\n        \"properties\": {\n          \"location\": {\n            \"type\": \"string\"\n          }\n        }\n      }\n    }\n  ],\n  \"model\": \"anthropic/claude-4.5-sonnet-20250929\",\n  \"temperature\": 0.7,\n  \"top_p\": 0.9\n}")

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

url = URI("https://openrouter.ai/api/v1/responses")

http = Net::HTTP.new(url.host, url.port)
http.use_ssl = true

request = Net::HTTP::Post.new(url)
request["Authorization"] = 'Bearer <token>'
request["Content-Type"] = 'application/json'
request.body = "{\n  \"input\": [\n    {\n      \"type\": \"message\",\n      \"role\": \"user\",\n      \"content\": \"Hello, how are you?\"\n    }\n  ],\n  \"tools\": [\n    {\n      \"type\": \"function\",\n      \"name\": \"get_current_weather\",\n      \"description\": \"Get the current weather in a given location\",\n      \"parameters\": {\n        \"type\": \"object\",\n        \"properties\": {\n          \"location\": {\n            \"type\": \"string\"\n          }\n        }\n      }\n    }\n  ],\n  \"model\": \"anthropic/claude-4.5-sonnet-20250929\",\n  \"temperature\": 0.7,\n  \"top_p\": 0.9\n}"

response = http.request(request)
puts response.read_body
```

```java
import com.mashape.unirest.http.HttpResponse;
import com.mashape.unirest.http.Unirest;

HttpResponse<String> response = Unirest.post("https://openrouter.ai/api/v1/responses")
  .header("Authorization", "Bearer <token>")
  .header("Content-Type", "application/json")
  .body("{\n  \"input\": [\n    {\n      \"type\": \"message\",\n      \"role\": \"user\",\n      \"content\": \"Hello, how are you?\"\n    }\n  ],\n  \"tools\": [\n    {\n      \"type\": \"function\",\n      \"name\": \"get_current_weather\",\n      \"description\": \"Get the current weather in a given location\",\n      \"parameters\": {\n        \"type\": \"object\",\n        \"properties\": {\n          \"location\": {\n            \"type\": \"string\"\n          }\n        }\n      }\n    }\n  ],\n  \"model\": \"anthropic/claude-4.5-sonnet-20250929\",\n  \"temperature\": 0.7,\n  \"top_p\": 0.9\n}")
  .asString();
```

```php
<?php
require_once('vendor/autoload.php');

$client = new \GuzzleHttp\Client();

$response = $client->request('POST', 'https://openrouter.ai/api/v1/responses', [
  'body' => '{
  "input": [
    {
      "type": "message",
      "role": "user",
      "content": "Hello, how are you?"
    }
  ],
  "tools": [
    {
      "type": "function",
      "name": "get_current_weather",
      "description": "Get the current weather in a given location",
      "parameters": {
        "type": "object",
        "properties": {
          "location": {
            "type": "string"
          }
        }
      }
    }
  ],
  "model": "anthropic/claude-4.5-sonnet-20250929",
  "temperature": 0.7,
  "top_p": 0.9
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

var client = new RestClient("https://openrouter.ai/api/v1/responses");
var request = new RestRequest(Method.POST);
request.AddHeader("Authorization", "Bearer <token>");
request.AddHeader("Content-Type", "application/json");
request.AddParameter("application/json", "{\n  \"input\": [\n    {\n      \"type\": \"message\",\n      \"role\": \"user\",\n      \"content\": \"Hello, how are you?\"\n    }\n  ],\n  \"tools\": [\n    {\n      \"type\": \"function\",\n      \"name\": \"get_current_weather\",\n      \"description\": \"Get the current weather in a given location\",\n      \"parameters\": {\n        \"type\": \"object\",\n        \"properties\": {\n          \"location\": {\n            \"type\": \"string\"\n          }\n        }\n      }\n    }\n  ],\n  \"model\": \"anthropic/claude-4.5-sonnet-20250929\",\n  \"temperature\": 0.7,\n  \"top_p\": 0.9\n}", ParameterType.RequestBody);
IRestResponse response = client.Execute(request);
```

```swift
import Foundation

let headers = [
  "Authorization": "Bearer <token>",
  "Content-Type": "application/json"
]
let parameters = [
  "input": [
    [
      "type": "message",
      "role": "user",
      "content": "Hello, how are you?"
    ]
  ],
  "tools": [
    [
      "type": "function",
      "name": "get_current_weather",
      "description": "Get the current weather in a given location",
      "parameters": [
        "type": "object",
        "properties": ["location": ["type": "string"]]
      ]
    ]
  ],
  "model": "anthropic/claude-4.5-sonnet-20250929",
  "temperature": 0.7,
  "top_p": 0.9
] as [String : Any]

let postData = JSONSerialization.data(withJSONObject: parameters, options: [])

let request = NSMutableURLRequest(url: NSURL(string: "https://openrouter.ai/api/v1/responses")! as URL,
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