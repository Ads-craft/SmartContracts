import { OpenAI } from "openai"
import * as dotenv from "dotenv"
import pinataSDK from "@pinata/sdk"
import { fileURLToPath } from "url"
import { dirname } from "path"

dotenv.config()
const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

const OPEN_AI_KEY = process.env.OPEN_AI_KEY

const openai = new OpenAI({
  apiKey: OPEN_AI_KEY,
})
const pinata = new pinataSDK(process.env.PINATA_API_KEY, process.env.PINATA_SECRET_KEY)

export const makeImagePromptRequest = async (textPrompt)=> {
  try {
    const imageGeneration = await openai.images.generate({
      model: "dall-e-3",
      prompt: textPrompt,
      n: 1,
      size: "1024x1024",
      quality: "standard",
    })
    const responseData = imageGeneration?.data
    const base64data = Buffer.from(responseData).toString("base64")
    const image = `data:image/png;base64,${base64data}`
    return image
  } catch (error) {
    console.log(error.message)
    return null
  }
}
export const makeTextPromptRequest= async(textPrompt)=> {
  try {
    const chatCompletion = await openai.chat.completions.create({
      messages: [{ role: "user", content: textPrompt }],
      model: "gpt-3.5-turbo",
    })
    const responseData = chatCompletion?.data
    return responseData
  } catch (error) {
    console.log(error.message)
    return null
  }
}

export const uploadPromptResultReturnIPFSHash =async(
  name,
  description,
  imageUrl,
  typeOfAd,
  niche,
  tagline,
  promoter,
  creator,
  hashTags,
  uniqueAdPrompt,
  createdAt
)=> {
  try {
    const primaryOptions = {
      name,
      description,
      uniqueAdPrompt: uniqueAdPrompt,
    }
    const imageIPFSData = await pinDataToIPFS(imageUrl, primaryOptions)
    const metadata = {
      ...primaryOptions,
      image: imageIPFSData.IpfsHash,
      attributes: [
        { trait_type: "type", value: typeOfAd },
        { trait_type: "niche", value: niche },
        { trait_type: "tagline", value: tagline },
        { trait_type: "promoter", value: promoter },
        { trait_type: "hash tags", value: hashTags },
        { trait_type: "creator", value: creator },
        { trait_type: "date", value: createdAt },
      ],
    }
    const jsonIPFSData = await pinDataToIPFS(metadata, metadata, (fileType = "json"))

    return { imageIPFSData, jsonIPFSData }
  } catch (error) {
    console.log(error.message)
    return null
  }
}

export const pinDataToIPFS = async (file, options, fileType = "image") => {
  try {
    const bodyOptions = {
      pinataMetadata: {
        name: options?.name,
        keyvalues: { ...options },
      },
      pinataOptions: {
        cidVersion: 0,
      },
    }
    const data =
      fileType === "image" ? await pinata.pinFileToIPFS(file, bodyOptions) : pinata.pinJSONToIPFS(file, bodyOptions)
    return data
  } catch (error) {
    console.log(error)
  }
}

export const getDataFromIPFSStore = async (hash = "") => {
  try {
    const result = Boolean(hash) ? await pinata.pinList({ hashContains: hash }) : await pinata.pinList()
    return result
  } catch (error) {
    console.log(error)
    return null
  }
}
