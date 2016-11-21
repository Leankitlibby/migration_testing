/****** Object:  UserDefinedFunction [dbo].[fn_Util_Get_BoardIds_for_Org_and_User]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON



RETURNS 
@boardIds TABLE 
(
	[BoardId] BIGINT NOT NULL PRIMARY KEY
)
AS
BEGIN
	DECLARE @userDimRowId BIGINT

	-- Find the DimRowId for the latest dimension record for this user
	SELECT @userDimRowId = MAX(dU.[DimRowId])
	FROM [dbo].[dim_User] dU 
	WHERE dU.[OrganizationId] = @organizationID 
	AND dU.[Id] = @userId 
	AND dU.[IsDeleted] = 0 
	AND dU.[Enabled] = 1 
	AND dU.[IsApproximate] = 0 
	AND dU.[ContainmentEndDate] IS NULL
	
	-- We found no user, return an empty result set
	IF (@userDimRowId IS NULL)
		RETURN

	DECLARE @isAccountOwner BIT = 0, @isOrgAdmin BIT = 0

	-- Grab metadata from the user to check permissions
	SELECT
		@isAccountOwner = dU.[IsAccountOwner]
		, @isOrgAdmin = dU.[Administrator]
	FROM [dbo].[dim_User] dU
	WHERE dU.[DimRowId] = @userDimRowId

	DECLARE @tmpBoardIds TABLE ([BoardId] BIGINT NOT NULL)

	-- If the user is the account owner or org admin, return all non-deleted, non-archived boards
	IF (@isAccountOwner = 1 OR @isOrgAdmin = 1)
		INSERT INTO @tmpBoardIds
		SELECT DISTINCT [Id]
		FROM [dbo].[dim_Board] dB
		WHERE dB.[OrganizationId] = @organizationID
		AND (dB.[IsDeleted] = 0 OR dB.[IsDeleted] IS NULL)
		AND dB.[IsArchived] = 0
		AND dB.[IsApproximate] = 0
		AND dB.[ContainmentEndDate] IS NULL
	ELSE
	BEGIN
		-- Add all boards for which the user has at least a read-only role
		INSERT INTO @tmpBoardIds
		SELECT DISTINCT dBR.[BoardId]
		FROM [dbo].[dim_BoardRole] dBR
		INNER JOIN [dbo].[dim_Board] dB
			ON dBR.[BoardId] = dB.[Id]
		WHERE dBR.[UserId] = @userId
		AND dB.[OrganizationId] = @organizationID
		AND (dB.[IsDeleted] = 0 OR dB.[IsDeleted] IS NULL)
		AND dB.[IsArchived] = 0
		AND dB.[IsApproximate] = 0
		AND dB.[ContainmentEndDate] IS NULL
		AND dBR.[RoleTypeId] > 0
		AND dBR.[IsApproximate] = 0
		AND (dBR.[IsDeleted] = 0 OR dBR.[IsDeleted] IS NULL)
		AND dBR.[ContainmentEndDate] IS NULL

		-- Add any shared boards that aren't in the list
		INSERT INTO @tmpBoardIds
		SELECT DISTINCT dB.[Id]
		FROM [dbo].[dim_Board] dB
		WHERE [dB].[OrganizationId] = @organizationID
		AND [dB].[IsShared] = 1
		AND [dB].[SharedBoardRole] > 0
		AND (dB.[IsDeleted] = 0 OR dB.[IsDeleted] IS NULL)
		AND dB.[IsArchived] = 0
		AND dB.[IsApproximate] = 0
		AND dB.[ContainmentEndDate] IS NULL
		
		-- Delete any boards for which the user has been assigned the "No Access" role
		DELETE @tmpBoardIds
		FROM @tmpBoardIds b
		INNER JOIN [dbo].[dim_BoardRole] dBR
			ON b.[BoardId] = dBR.[BoardId]
		WHERE dBR.[UserId] = @userId
		AND dBR.[RoleTypeId] = 0
		AND dBR.[IsApproximate] = 0
		AND (dBR.[IsDeleted] = 0 OR dBR.[IsDeleted] IS NULL)
		AND dBR.[ContainmentEndDate] IS NULL
	END

	INSERT INTO @boardIds
	SELECT DISTINCT [BoardId]
	FROM @tmpBoardIds

	RETURN 
END

GO
