// ReadmeMobileFormatterTests.swift
import Foundation

#if DEBUG
/// Test cases for ReadmeMobileFormatter to ensure proper functionality
enum ReadmeMobileFormatterTests {
    
    static func runTests() {
        print("🧪 Running ReadmeMobileFormatter tests...")
        
        testFrontmatterPreservation()
        testTableTransformation()
        testHTMLResponsiveness()
        testCodeBlockPreservation()
        testCompleteExample()
        
        print("✅ All ReadmeMobileFormatter tests passed!")
    }
    
    private static func testFrontmatterPreservation() {
        let input = """
        ---
        title: Test Model
        license: MIT
        ---
        
        # My Model
        
        This is a test.
        """
        
        let result = ReadmeMobileFormatter.transform(input)
        assert(result.hasPrefix("---\ntitle: Test Model\nlicense: MIT\n---\n"), "Frontmatter not preserved")
        print("✓ Frontmatter preservation test passed")
    }
    
    private static func testTableTransformation() {
        let input = """
        | Model | Parameters | License |
        |-------|------------|---------|
        | GPT-4 | 175B | OpenAI |
        | Llama | 7B | Meta |
        """
        
        let result = ReadmeMobileFormatter.transform(input)
        assert(result.contains("**GPT-4**"), "Table first column not converted to bold heading")
        assert(result.contains("- **Parameters:** 175B"), "Table cell not converted to list format")
        assert(result.contains("- **License:** OpenAI"), "Table cell not converted to list format")
        print("✓ Table transformation test passed")
    }
    
    private static func testHTMLResponsiveness() {
        let input = """
        <div style="display: flex; gap: 10px;">
            <img src="image1.jpg" width="300" alt="Test">
            <img src="image2.jpg" width="400" alt="Test2">
        </div>
        """
        
        let result = ReadmeMobileFormatter.transform(input)
        assert(result.contains("flex-wrap: wrap"), "flex-wrap not added to flex container")
        assert(result.contains("max-width: 300px"), "Image width not converted to max-width")
        assert(result.contains("height: auto"), "height: auto not added to image")
        assert(!result.contains("width=\"300\""), "Original width attribute not removed")
        print("✓ HTML responsiveness test passed")
    }
    
    private static func testCodeBlockPreservation() {
        let input = """
        Here's some code:
        
        ```python
        | This | Should | Not | Be | Transformed |
        |------|--------|-----|----|-----------| 
        print("Hello")
        ```
        
        | But | This | Should |
        |-----|------|--------|
        | Data | Be | Transformed |
        """
        
        let result = ReadmeMobileFormatter.transform(input)
        assert(result.contains("| This | Should | Not | Be | Transformed |"), "Table in code block was transformed")
        assert(result.contains("**Data**"), "Table outside code block was not transformed")
        print("✓ Code block preservation test passed")
    }
    
    private static func testCompleteExample() {
        let input = """
        ---
        title: Unsloth Gemma Models
        license: Apache 2.0
        ---
        
        # Unsloth Gemma Models
        
        Here's a comparison table:
        
        | Unsloth supports          |    Free Notebooks                                                                                           | Performance | Memory use |
        |-----------------|--------------------------------------------------------------------------------------------------------------------------|-------------|----------|
        | **Gemma 3 (4B)**      | [▶️ Start on Colab](https://colab.research.google.com/github/unslothai/notebooks/blob/main/nb/Gemma3_(4B).ipynb)               | 2x faster | 80% less |
        | **Gemma-3n-E4B**      | [▶️ Start on Colab](https://colab.research.google.com/github/unslothai/notebooks/blob/main/nb/Gemma3N_(4B)-Conversational.ipynb)               | 2x faster | 60% less |
        
        And some images:
        
        <div style="display: flex; gap: 5px; align-items: center; ">
            <img src="image1.jpg" width="133" alt="Test">
            <img src="image2.jpg" width="173" alt="Test2">
        </div>
        
        And a code block with a table that should NOT be transformed:
        
        ```markdown
        | This | Should | Stay | As | Table |
        |------|--------|------|----|-------|
        | Data | In | Code | Block | Here |
        ```
        
        And some standard markdown elements that should be preserved:
        
        ## This is a heading
        - This is a list item
        - Another list item
        
        > This is a blockquote
        
        Regular paragraph text.
        """
        
        let result = ReadmeMobileFormatter.transform(input)
        
        // Test frontmatter preservation
        assert(result.hasPrefix("---\ntitle: Unsloth Gemma Models\nlicense: Apache 2.0\n---\n"), "Frontmatter not preserved")
        
        // Test table transformation
        assert(result.contains("**Gemma 3 (4B)**"), "First table row heading not converted")
        assert(result.contains("- **Free Notebooks:** [▶️ Start on Colab]"), "First table cell not converted to list")
        assert(result.contains("- **Performance:** 2x faster"), "Performance cell not converted")
        assert(result.contains("- **Memory use:** 80% less"), "Memory use cell not converted")
        
        assert(result.contains("**Gemma-3n-E4B**"), "Second table row heading not converted")
        assert(result.contains("- **Memory use:** 60% less"), "Second row memory use not converted")
        
        // Test HTML responsiveness
        assert(result.contains("flex-wrap: wrap"), "flex-wrap not added to flex container")
        assert(result.contains("max-width: 133px"), "First image width not converted to max-width")
        assert(result.contains("max-width: 173px"), "Second image width not converted to max-width")
        assert(result.contains("height: auto"), "height: auto not added to images")
        assert(!result.contains("width=\"133\""), "Original width attribute not removed")
        assert(!result.contains("width=\"173\""), "Original width attribute not removed")
        
        // Test code block preservation
        assert(result.contains("| This | Should | Stay | As | Table |"), "Table in code block was transformed")
        assert(result.contains("| Data | In | Code | Block | Here |"), "Table in code block was transformed")
        
        // Test standard markdown preservation (Rule 4)
        assert(result.contains("## This is a heading"), "Heading not preserved")
        assert(result.contains("- This is a list item"), "List items not preserved")
        assert(result.contains("> This is a blockquote"), "Blockquote not preserved")
        assert(result.contains("Regular paragraph text."), "Paragraph text not preserved")
        
        print("✓ Complete example test passed")
    }
}
#endif
