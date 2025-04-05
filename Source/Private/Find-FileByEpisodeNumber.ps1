Function Find-FileByEpisodeNumber {
    [CmdletBinding()]
    [OutputType([System.IO.FileInfo])]
    param (
        [Parameter(
            Mandatory
        )]
        $fileList,

        [Parameter(
            Mandatory
        )]
        [string]
        $FullEpisodeNumber
    )

    Write-Verbose "Starting Find-FileByEpisodeNumber function"
    Write-Debug "Checking for Episode $FullEpisodeNumber"

    # Get Season number from $FullEpisodeNumber
    $seasonNumber = $FullEpisodeNumber -match '[sS]\d{2}' | Select-Object -First 1 | ForEach-Object {
        # Returns Section of the String that the Regex Validated
        $Matches.Values
    }

    # Get Season number from $FullEpisodeNumber
    $episodeNumber = $FullEpisodeNumber -match '[eE]\d{2}' | Select-Object -First 1 | ForEach-Object {
        # Returns Section of the String that the Regex Validated
        $Matches.Values
    }
  
    foreach ($file in $fileList) {
        Write-Debug "Checking File: $($file.FullName)"

        # See if File Matches Correct Season Number
        $seasonLocatedInFileName = (
            $file.Name -match '[sS]\d{2}' | Select-Object -First 1 | ForEach-Object {
                # Returns Section of the String that the Regex Validated
                $Matches.Values
            }
        )
        Write-Debug "Season Found in File Name: $seasonLocatedInFileName"

        # Check to see if Found Season Matches Season we are Looking For.
        $seasonMatch = ($seasonLocatedInFileName -eq $seasonNumber)

        if (-not $seasonMatch) {
            Write-Debug "Incorrect Season.  Skipping to next file."
            continue
        }

        # See if File Matches Correct Episode Number
        $episodeLocatedInFileName = (
            $file.Name -match '[eE]\d{2}' | Select-Object -First 1 | ForEach-Object {
                # Returns Section of the String that the Regex Validated
                $Matches.Values
            }
        )

        # Check to see if Found Season Matches Season we are Looking For.
        $episodeMatch = ($episodeLocatedInFileName -eq $episodeNumber)
                
        if (-not $episodeMatch) {
            Write-Debug "Incorrect Season.  Skipping to next file."
            continue
        }

        # Find file that contains both correct season & episode name
        if ($seasonMatch -and $episodeMatch) {
            Write-Debug "File Found: $($file.Name)"
            # Return found Object
            $file

            # Exit function and continue script
            break                
        }

        Write-Verbose "Unable to detect Season and Episode from file name."
        Write-Verbose "Checking to see if file is in '1x01' format without the S or E in the name."


        # Check if file is in "1x01" (or other separator) format without the S or E in the name.
        $noLabelEpisodeNumber = ($file.Name -match '\s\d{1,2}[-x.]\d{1,2}\s')

        if ($noLabelEpisodeNumber) {

            $regexResults = $noLabelEpisodeNumber | Select-Object -First 1 | ForEach-Object { $Matches.Values }
            $regexResultsSeason = "S$("{0:D2}" -f [int]($regexResults.trim() -split '\D')[0])"
            $regexResultsEpisode = "E$("{0:D2}" -f [int]($regexResults.trim() -split '\D')[1])"

            # Check if file matches correct season and episode number
            if ("$regexResultsSeason.$regexResultsEpisode" -eq $FullEpisodeNumber) {
                # Return found Object
                $file

                # Exit function and continue script
                break
            }
        }

        Write-Verbose "Trying to find Season number from Parent folder and Episode Number From File."

        # If season cannot be found in episode name try pulling it from parent folder.
        if (-not($seasonLocatedInFileName)) {
            # Verify Parent Directory is not null
            if ($file.Directory) {
                Write-Verbose "Trying to Find Season Number from Parent Directory and Episode Number from File"
                # Match season folder
                $seasonFolderMatch = (
                    # Convert season folder number to 2 digits and add 'S' before the number.
                    "S{0:D2}" -f [int64](
                        # Remove everything from Season folder Name except numbers and spaces
                        # Then grab the first group of numbers before a space
                        (
                                (Split-Path $file.Directory -Leaf) -replace '[^0-9$ ]', ''
                        ).TrimStart().Split(' ')[0]
                    )
                ) -eq $FullEpisodeNumber.Split('.')[0]

                # Match episode number when there is no season in the episode name.
                $episodeNoSeasonMatch = (
                    # Convert episode number to two digits and add 'E' before the number.
                    "E{0:D2}" -f [int64](
                        # Remove everything from episode folder Name except numbers and spaces
                        # Then grab the first group of numbers before a space
                        (
                            $file.Name -replace '[^0-9$ ]', ''
                        ).TrimStart().Split(' ')[0]
                    )
                ) -eq $FullEpisodeNumber.Split('.')[-1]

                # Check if correct episode file is found without season in episode name
                if ($seasonFolderMatch -and $episodeNoSeasonMatch) {
                    # Return found Object
                    $file

                    # Exit function and continue script
                    return
                }
            }
        }

        Write-Verbose "Executed all checks to detect Season and Episode from filename."
    }
}