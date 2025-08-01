-- TODO Add keywords
local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrLogger = import 'LrLogger'
local LrApplication = import "LrApplication"
local LrErrors = import "LrErrors"
local LrDialogs = import "LrDialogs"
local LrView = import "LrView"
local LrTasks = import "LrTasks"
local LrFunctionContext = import "LrFunctionContext"
local LrFileUtils = import 'LrFileUtils'
local LrStringUtils = import 'LrStringUtils'
local LrBinding = import "LrBinding"
local LrColor = import "LrColor"

local logger = LrLogger('LrLlama')
logger:enable("logfile") -- Logs to ~/Documents/LrClassicLogs | tail -f LrLlama.log

local model = "minicpm-v"

logger:info("Initializing Lightroom Llama Plugin")

JSON = (assert(loadfile(LrPathUtils.child(_PLUGIN.path, "JSON.lua"))))()

local function exportThumbnail(photo)
    local tempPath = LrFileUtils.chooseUniqueFileName(LrPathUtils.getStandardFilePath('temp') .. "/thumbnail.jpg")

    local success, result = photo:requestJpegThumbnail(512, 512, function(jpegData)
        -- Save the JPEG thumbnail to the temporary file
        if jpegData then
            local tempFile = io.open(tempPath, "wb")
            tempFile:write(jpegData)
            tempFile:close()
            logger:info("Thumbnail saved to " .. tempPath)
            return true
        end
        return false
    end)

    if success then
        return tempPath
    else
        logger:warn("Failed to export thumbnail")
        return nil
    end
end

local function base64EncodeImage(imagePath)

    -- Read the image file as binary
    local file = io.open(imagePath, "rb") -- Open the file in binary mode
    if not file then
        LrDialogs.message("Error", "Could not open file: " .. imagePath, "critical")
        return
    end

    local binaryData = file:read("*all") -- Read the entire file as binary data
    file:close() -- Close the file

    -- Encode the binary data to Base64
    local base64Data = LrStringUtils.encodeBase64(binaryData)

    return base64Data
end


---@param photo LrPhoto The photo to send to the API
---@param prompt string The prompt to send to the API
---@param currentData table (optional) The current title, caption, and keywords of the photo
---@param useCurrentData boolean (optional) Whether to use the current title and caption
---@param useSystemPrompt boolean (optional) Whether to use the system prompt
---@return table response The response from the API
local function sendDataToApi(photo, prompt, currentData, useCurrentData, useSystemPrompt)
    logger:info("Sending data to API")
    local encodedImage = base64EncodeImage(exportThumbnail(photo))
    local url = "http://localhost:11434/api/generate"

    -- Define data to be sent (as a Lua table)
    local postData = {
        model = model,
        prompt =  (useCurrentData and "Title: "..currentData.title .. " Caption: "..currentData.caption .. prompt) or prompt,
        format = "json",
        system = useSystemPrompt and [[You are an AI tasked with creating a JSON object containing a `title`, a `caption`, and a list of `keywords` based on a given piece of content (such as an image or video). ]] ..
        (useCurrentData and [[The content currently has the following metadata which you need to implement and improve upon. It is important to keep the title and caption as close to this as possible.
Current title: "]] .. (currentData.title or "") .. [["
Current caption: "]] .. (currentData.caption or "") .. [["

]] or "") .. [[Please follow these detailed guidelines for creating excellent metadata:

1. **Title (Description):**
   - Provide a unique, descriptive title for the content.
   - The title should answer the Who, What, When, Where, and Why of the content.
   - It should be written as a sentence or phrase, similar to a news headline, capturing the key details, mood, and emotions of the scene.
   - Do not list keywords in the title. Avoid repetition of words and phrases.
   - Include helpful details such as the angle, focus, and perspective if relevant.
   - Do not include :.
   - If given, use the current title as a starting point.

2. **Caption:**
   - Provide a more detailed description or context for the content. This can be a fuller explanation of the title, including any relevant background or emotional tone that helps convey the essence of the scene.
   - If given, use the current caption as a starting point.

3. **Keywords:**
   - Provide a list of 7 to 50 keywords.
   - Keywords should be specific and directly related to the content.
   - Include broader topics, feelings, concepts, or associations represented by the content.
   - Avoid using unrelated terms or repeating words or compound words.
   - Do not include links, camera information, or trademarks unless required for editorial content.

### JSON Format:
```json
{
  "title": "string",
  "caption": "string",
  "keywords": ["string"]
}
```

### Example:
```json
{
  "title": "A serene sunset over a peaceful beach with golden skies",
  "caption": "A calm evening beach scene with a golden sunset reflecting on the ocean waves, creating a peaceful and tranquil mood. The horizon is clear with soft, pastel colors blending into the blue sky.",
  "keywords": ["sunset", "beach", "calm", "ocean", "serene", "golden skies", "peaceful", "tranquil", "pastel colors", "horizon", "evening"]
}
```

Use this structure and guidelines to generate titles, captions, and keywords that are descriptive, unique, and accurate.]]
or
[[You are an AI tasked with creating a JSON object containing a `title`, a `caption`, and a list of `keywords` based on a given piece of content (such as an image or video).

### JSON Format:
```json
{
  "title": "string",
  "caption": "string",
  "keywords": ["string"]
}
```
]],
        images = {encodedImage},
        stream = false
    }

    logger:info("Post data: " .. JSON:encode(postData))

    -- Convert the Lua table to a JSON string
    local jsonPayload = JSON:encode(postData)

    -- Make a POST request
    local response, headers = LrHttp.post(url, jsonPayload, {{
        field = "Content-Type",
        value = "application/json"
    }})

    if response then
        local response_data = JSON:decode(response)
        local response_json = JSON:decode(response_data.response)
        return response_json
    else
        LrDialogs.message("Error", "Failed to send data to the API.", "critical")
        return "Error: Failed to send data to the API."
    end
end

local function addKeywordsWithParent(catalog, photo, keywords)
    if keywords and type(keywords) == "table" then
        -- First create or get the parent 'llm' keyword
        local llmKeyword = catalog:createKeyword("llm", nil, true, nil, true)

        for _, keyword in ipairs(keywords) do
            if keyword and keyword ~= "" then
                -- Create child keyword under 'llm' parent
                local childKeyword = catalog:createKeyword(keyword, nil, true, llmKeyword, true)
                -- Add the keyword object to the photo
                photo:addKeyword(childKeyword)
            end
        end
    end
end

local function main()
    -- Get the active catalog
    local catalog = LrApplication.activeCatalog()

    -- Get the selected photo
    local selectedPhotos = catalog:getTargetPhotos() -- Gets all selected photos
    if #selectedPhotos == 0 then
        LrDialogs.message("No photo selected", "Please select a photo to view.", "critical")
        return
    end

    -- Get the first selected photo (if multiple, you can modify the code for more)
    local selectedPhoto = selectedPhotos[1]
    local thumbnailPath = exportThumbnail(selectedPhoto)

    LrFunctionContext.callWithContext("showLlamaDialog", function(context)
        local props = LrBinding.makePropertyTable(context)
        props.status = "Ready"
        props.statusColor = LrColor(0.149, 0.616, 0.412)
        props.prompt = "Caption this photo"
        props.title = selectedPhoto:getFormattedMetadata('title')
        props.caption = selectedPhoto:getFormattedMetadata('caption')
        props.keywords = ""
        props.response = ""
        props.useCurrentData = props.title ~= "" or props.caption ~= ""
        props.useSystemPrompt = true

        -- Create a view factory
        local f = LrView.osFactory()

        -- Define the dialog contents
        local c = f:view{
            bind_to_object = props,
            f:row{f:column{
                f:picture{
                    value = thumbnailPath,
                    frame_width = 2,
                    width = 400,
                    height = 400
                },
                width = 400
            }, f:spacer{
                width = 10
            }, f:column{
                f:column{f:static_text{
                    title = "Title:"
                }, f:spacer{f:label_spacing{}}, f:edit_field{
                    value = LrView.bind("title"), -- Bind to the new response property
                    width = 400
                }},
                f:spacer{
                    height = 10
                },
                f:static_text{
                    title = "Caption:",
                    alignment = 'left'
                },
                f:spacer{f:label_spacing{}},
                f:edit_field{
                    value = LrView.bind("caption"), -- Bind to the new response property
                    width = 400,
                    height = 100
                },
                f:spacer{
                    height = 10
                },
                f:static_text{
                    title = "Keywords:",
                    alignment = 'left'
                },
                f:spacer{f:label_spacing{}},
                f:edit_field{
                    value = LrView.bind("keywords"),
                    width = 400,
                    height = 60
                },
                f:spacer{
                    height = 10
                },
                f:separator{
                    width = 400
                },
                f:spacer{
                    height = 10
                },
                f:static_text{
                    title = "Prompt:",
                    alignment = 'left'
                },
                f:spacer{f:label_spacing{}},
                f:edit_field{
                    value = LrView.bind("prompt"),
                    width = 400,
                    height = 60
                },
                f:spacer{
                    height = 10
                },
                f:checkbox{
                    title = "Use current title and caption",
                    value = LrView.bind("useCurrentData")
                },
                f:spacer{
                    height = 10
                },
                f:checkbox{
                    title = "Use system prompt",
                    value = LrView.bind("useSystemPrompt")
                },
                f:spacer{
                    height = 10
                },
                f:separator{
                    width = 400
                },
                f:spacer{
                    height = 10
                },
                f:row{f:static_text{
                    title = "Model: " .. model,
                    fill_horizontal = 1
                }, f:static_text{
                    alignment = 'right',
                    title = LrView.bind("status"),
                    width = 200,
                    font = "<system/bold>",
                    text_color = LrView.bind("statusColor")
                }},
                f:spacer{
                    height = 10
                },
                f:row{f:push_button{
                    title = "Generate",
                    action = function()
                        props.status = "The llama is thinking..."
                        props.statusColor = LrColor(0.439, 0.345, 0.745)

                        LrTasks.startAsyncTask(function()
                            local apiResponse = sendDataToApi(selectedPhoto, props.prompt, {
                                title = props.title,
                                caption = props.caption,

                            },props.useCurrentData,
                        props.useSystemPrompt)
                            props.response = apiResponse
                            props.title = apiResponse.title
                            props.caption = apiResponse.caption
                            -- Convert keywords array to comma-separated string for display
                            if apiResponse.keywords and type(apiResponse.keywords) == "table" then
                                props.keywords = table.concat(apiResponse.keywords, ", ")
                            else
                                props.keywords = ""
                            end
                            props.status = "Ready"
                            props.statusColor = LrColor(0.149, 0.616, 0.412)
                        end)
                    end
                }},
                f:spacer{
                    height = 20
                },
                width = 400
            }}
        }

        -- Show the dialog
        local result = LrDialogs.presentModalDialog({
            title = "Lightroom Llama",
            contents = c,
            actionVerb = "Save"
        })


        if result == "ok" then
            -- Save the metadata to the photo
            catalog:withWriteAccessDo("Save Llama metadata", function()
                selectedPhoto:setRawMetadata("title", props.title)
                selectedPhoto:setRawMetadata("caption", props.caption)
                -- Parse keywords from comma-separated string and add with llm parent
                if props.keywords and props.keywords ~= "" then
                    local keywordList = {}
                    for keyword in string.gmatch(props.keywords, "([^,]+)") do
                        table.insert(keywordList, keyword:match("^%s*(.-)%s*$")) -- trim whitespace
                    end
                    addKeywordsWithParent(catalog, selectedPhoto, keywordList)
                end
            end)

            LrDialogs.message("Metadata Saved", "Title, caption, and keywords have been saved to the photo.", "info")
        end
    end)
end

LrTasks.startAsyncTask(main)
