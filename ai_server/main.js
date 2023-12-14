import app from "./server.js"
import {getDataFromIPFSStore} from "./imageGenUpload.js"

async function main() {
  const data = await getDataFromIPFSStore()
  console.log(data)
}

main().catch((error) => {
  console.log(error)
  process.exit(1)
})
