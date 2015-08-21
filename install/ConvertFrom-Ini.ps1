function ConvertFrom-Ini
{
  Param(
    [Parameter(Mandatory=$true,ValueFromPipeline=$true)]
    [string] $InputObject
  )
  process
  {
    $config = [ordered]@{}
    $InputObject -split "`n" | Foreach {
      switch -regex ($_)
      {
        '(.+?)\s*=\s*"(.*)"' # Key
        {
            $name,$value = $matches[1..2]
            $config[$name] = $value
        }
      }
    }
    return $config
  }
}
