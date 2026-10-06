@{
    Severity     = @('Error', 'Warning')
    ExcludeRules = @(
        # Console output of a one-shot provisioning script; the transcript captures it.
        'PSAvoidUsingWriteHost',
        # Microsoft's documented one-liners for install-powershell.ps1 and Chocolatey.
        'PSAvoidUsingInvokeExpression',
        # Install-Runners / Install-BaseTools read better plural.
        'PSUseSingularNouns',
        # Internal helpers of a non-interactive script; -WhatIf is meaningless here.
        'PSUseShouldProcessForStateChangingFunctions'
    )
}
