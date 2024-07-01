export const addressToBytes32 = (address: string) => {
    const prefixLessAddress = cutPrefix(address);

    return `0x${`1${prefixLessAddress}`.padStart(64, "0")}`
}

export const cutPrefix = (data: string) => {
    if (data.startsWith("0x")) {
        return data.slice(2)
    } else {
        return data;
    }
}