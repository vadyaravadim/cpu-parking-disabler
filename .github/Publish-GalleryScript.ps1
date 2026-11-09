function Publish-GalleryScript {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Version,
        [Parameter(Mandatory)][string]$NuGetApiKey
    )
    $gallery = 'PSGallery'
    $name = [IO.Path]::GetFileNameWithoutExtension($Path)
    if (-not (Find-Script -Name $name -RequiredVersion $Version -Repository $gallery -ErrorAction SilentlyContinue)) {
        Publish-Script -Path $Path -NuGetApiKey $NuGetApiKey -Repository $gallery
        return "Published $name $Version to $gallery"
    }
    $saved = New-Item -ItemType Directory -Path (Join-Path ([IO.Path]::GetTempPath()) ([guid]::NewGuid()))
    Save-Script -Name $name -RequiredVersion $Version -Repository $gallery -Path $saved.FullName
    if ((Get-FileHash -LiteralPath (Join-Path $saved.FullName "$name.ps1")).Hash -ne (Get-FileHash -LiteralPath $Path).Hash) {
        throw "$name $Version is already on $gallery with different content - release the next version"
    }
    "$name $Version is already on $gallery with identical content - not published again"
}
