/****** Object:  UserDefinedFunction [dbo].[fn_Util_Get_BoardIds_for_Org_and_User]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fn_Util_Get_BoardIds_for_Org_and_User]
(
	@organizationID	BIGINT	= -1
	, @userId		BIGINT	= -1
)
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
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_CardBlockedPeriods_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[fnCustomReporting_CardBlockedPeriods_0_2] 
(	
	@organizationId BIGINT
)
RETURNS @cardBlockedPeriods TABLE
(
	[Card ID] BIGINT
	, [Duration Seconds] BIGINT
	, [Blocked From Date] DATETIME
	, [Blocked To Date] DATETIME
	, [Card Title] NVARCHAR(255)
	, [Card Size] INT
	, [Card Priority] VARCHAR(10)
	, [Custom Icon ID] BIGINT
	, [Custom Icon Title] NVARCHAR(255)
	, [Card Type ID] BIGINT
	, [Card Type Title] NVARCHAR(255)
	, [Board ID] BIGINT
	, [Board Title] NVARCHAR(255)
	, [Blocked By User ID] BIGINT
	, [Blocked By User Email Address] NVARCHAR(255)
	, [Blocked By User Full Name] NVARCHAR(255)
	, [Unblocked By User ID] BIGINT
	, [Unblocked By User Email Address] NVARCHAR(255)
	, [Unblocked By User Full Name] NVARCHAR(255)
	, [Total Blocked Duration (Days)] INT
	, [Total Blocked Duration (Hours)] BIGINT
	, [Total Blocked Duration Minus Weekends (Days)] INT
	, [Blocked Reason] NVARCHAR(1000)
	, [Unblocked Reason] NVARCHAR(1000)
) 
AS
BEGIN
	
	WITH cte AS
	(
		SELECT
		[CB].[CardID] AS [Card ID],
		[CB].[StartDateKey],
		[CB].[DurationSeconds] AS [Duration Seconds],
		[CB].[ContainmentStartDate] AS [Blocked From Date],
		[CB].[ContainmentEndDate] AS [Blocked To Date],
		[C].[Title] AS [Card Title],
		[C].[Size] AS [Card Size],
		(CASE [C].[Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Card Priority],
		[C].[ClassOfServiceId] AS [Custom Icon ID],
		[COS].[Title] AS [Custom Icon Title],
		[C].[TypeId] AS [Card Type ID],
		[CT].[Name] AS [Card Type Title],
		[B].[Id] AS [Board ID],
		[B].[Title] AS [Board Title],
		[CB].[StartUserId] [Blocked By User ID],
		[BU].[EmailAddress] AS [Blocked By User Email Address],
		[BU].[LastName] + ', ' + [BU].[FirstName] AS [Blocked By User Full Name],
		[CB].[EndUserId] AS [Unblocked By User ID],
		[UBU].[EmailAddress] AS [Unblocked By User Email Address],
		[UBU].[LastName] + ', ' + [UBU].[FirstName] AS [Unblocked By User Full Name],
		'' AS [Blocked Reason],
		'' AS [Unblocked Reason],
		DATEDIFF(DAY, [CB].[ContainmentStartDate] , ISNULL([CB].[ContainmentEndDate], GETUTCDATE())) AS [Total Blocked Duration (Days)],
		DATEDIFF(HOUR, [CB].[ContainmentStartDate], ISNULL([CB].[ContainmentEndDate], GETUTCDATE())) AS [Total Blocked Duration (Hours)],
		DATEDIFF(DAY, [CB].[ContainmentStartDate], ISNULL([CB].[ContainmentEndDate], GETUTCDATE())) - (DATEDIFF(WEEK, [CB].[ContainmentStartDate], ISNULL([CB].[ContainmentEndDate], GETUTCDATE())) * 2) - 
			CASE WHEN DATEPART(dw,[CB].[ContainmentStartDate]) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,ISNULL([CB].[ContainmentEndDate], GETUTCDATE())) = 1 THEN 1 ELSE 0 END AS [Total Blocked Duration Minus Weekends (Days)],
		ROW_NUMBER() OVER(PARTITION BY [CB].[CardID], [CB].[StartDateKey] ORDER BY [CB].[ContainmentStartDate] desc) rn
		FROM [fact_CardBlockContainmentPeriod] [CB]
		JOIN [dim_Card] [C] ON [C].[Id] = [CB].[CardID]
			JOIN [dim_Lane] [L] ON [L].[Id] = [C].[LaneId]
			JOIN [dim_Board] [B] ON [B].[Id] = [L].[BoardId]
			JOIN [dim_Organization] [O] ON [O].[Id] = [B].[OrganizationId]
			JOIN [dim_CardTypes] [CT] ON [CT].[Id] = [C].[TypeId]
			LEFT JOIN [dim_ClassOfService] [COS] ON [COS].[Id] = [C].[ClassOfServiceId]
			JOIN [dim_User] [BU] ON [BU].[Id] = [CB].[StartUserId]
			LEFT JOIN [dim_User] [UBU] ON [UBU].[Id] = [CB].[EndUserId]
		WHERE [O].[Id] = @organizationId
			AND [O].[ContainmentEndDate] IS NULL
			AND [O].[IsApproximate] = 0
			AND [B].[ContainmentEndDate] IS NULL
			AND [B].[IsApproximate] = 0 
			AND [L].[ContainmentEndDate] IS NULL
			AND [L].[IsApproximate] = 0
			AND [L].[TaskBoardId] IS NULL
			AND [C].[ContainmentEndDate] IS NULL
			AND [C].[IsApproximate] = 0
			AND [CT].[ContainmentEndDate] IS NULL
			AND [CT].[IsApproximate] = 0
			AND [COS].[ContainmentEndDate] IS NULL
			AND ([COS].[IsApproximate] IS NULL OR [COS].[IsApproximate] = 0)
			AND [CB].[IsApproximate] = 0
			AND [BU].[ContainmentEndDate] IS NULL
			AND [BU].[IsApproximate] = 0
			AND [UBU].[ContainmentEndDate] IS NULL
			AND ([UBU].[IsApproximate] IS NULL OR [UBU].[IsApproximate] = 0)
	)
	INSERT INTO @cardBlockedPeriods
	SELECT 
	  [Card ID]
	, [Duration Seconds]
	, [Blocked From Date]
	, [Blocked To Date]
	, [Card Title]
	, [Card Size]
	, [Card Priority]
	, [Custom Icon ID]
	, [Custom Icon Title]
	, [Card Type ID]
	, [Card Type Title]
	, [Board ID]
	, [Board Title]
	, [Blocked By User ID]
	, [Blocked By User Email Address]
	, [Blocked By User Full Name]
	, [Unblocked By User ID]
	, [Unblocked By User Email Address]
	, [Unblocked By User Full Name]
	, [Total Blocked Duration (Days)]
	, [Total Blocked Duration (Hours)]
	, [Total Blocked Duration Minus Weekends (Days)]
	, [Blocked Reason]
	, [Unblocked Reason]
	FROM cte WHERE rn = 1

	UPDATE @cardBlockedPeriods
	SET [Blocked Reason]
	=
	ISNULL((
		SELECT TOP 1 [BlockReason]
		FROM [dim_Card] [BC] 
		WHERE
		[BC].[Id] = [Card ID] 
		AND [BC].[ContainmentStartDate] 
			BETWEEN [Blocked From Date] 
			AND ISNULL([Blocked To Date], GETUTCDATE())
		AND [BC].[IsBlocked] = 1 AND [BC].[BlockReason] IS NOT NULL
		ORDER BY [ContainmentStartDate] DESC
	), '')

	UPDATE @cardBlockedPeriods
	SET [Unblocked Reason]
	=
	ISNULL((
		SELECT TOP 1 [BlockReason] 
		FROM [dim_Card] [BC] 
		WHERE
		[BC].[Id] = [Card ID]
		AND [BC].[ContainmentStartDate] 
			BETWEEN [Blocked From Date] 
			AND ISNULL([Blocked To Date], GETUTCDATE())
		AND [BC].[IsBlocked] = 0
		ORDER BY [ContainmentStartDate] DESC
	), '')

	RETURN
 --Each card should only appear once per day, either blocked or unblocked

END

GO
/****** Object:  UserDefinedFunction [dbo].[fnDetermineBurnupFinishLane]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnDetermineBurnupFinishLane] 
(
	@boardId BIGINT,
	@providedFinishLane BIGINT = 0
)
RETURNS BIGINT
AS
BEGIN

	IF NULLIF(@providedFinishLane,0) IS NULL
	BEGIN
		SELECT TOP 1 @providedFinishLane = LaneId
		FROM [dbo].[fnGetLaneOrder](@boardId)
		WHERE (TopLevelOrder = 3 OR IsDoneLane = 1)
		ORDER BY LaneRank

	END

	RETURN @providedFinishLane

END 


GO
/****** Object:  UserDefinedFunction [dbo].[fnDetermineBurnupFinishLane_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[fnDetermineBurnupFinishLane_0_2] 
(
	@boardId BIGINT,
	@providedFinishLane BIGINT = 0
)
RETURNS BIGINT
AS
BEGIN

	IF NULLIF(@providedFinishLane,0) IS NULL
	BEGIN
		SELECT TOP 1 @providedFinishLane = LaneId
		FROM [dbo].[fnGetLaneOrder_0_2](@boardId)
		WHERE (TopLevelOrder = 3 OR IsDoneLane = 1)
		ORDER BY LaneRank

	END

	RETURN @providedFinishLane

END

GO
/****** Object:  UserDefinedFunction [dbo].[fnDetermineBurnupStartLane]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnDetermineBurnupStartLane] 
(
	@boardId BIGINT,
	@providedStartLaneId BIGINT = 0
)
RETURNS BIGINT
AS
BEGIN
	
	--Get the startLaneId if not specified
	--this will be the backlog by default
	IF NULLIF(@providedStartLaneId,0) IS NULL
	BEGIN
		SELECT TOP 1 @providedStartLaneId = LaneId
		FROM [dbo].[fnGetLaneOrder](@boardId)
		WHERE TopLevelOrder = 1
		ORDER BY LaneRank
	END

	RETURN @providedStartLaneId

END 


GO
/****** Object:  UserDefinedFunction [dbo].[fnDetermineBurnupStartLane_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO

CREATE FUNCTION [dbo].[fnDetermineBurnupStartLane_0_2] 
(
	@boardId BIGINT,
	@providedStartLaneId BIGINT = 0
)
RETURNS BIGINT
AS
BEGIN
	
	--Get the startLaneId if not specified
	--this will be the backlog by default
	IF NULLIF(@providedStartLaneId,0) IS NULL
	BEGIN
		SELECT TOP 1 @providedStartLaneId = LaneId
		FROM [dbo].[fnGetLaneOrder_0_2](@boardId)
		WHERE TopLevelOrder = 1
		ORDER BY LaneRank
	END

	RETURN @providedStartLaneId

END

GO
/****** Object:  UserDefinedFunction [dbo].[fnGetBurnupTrendLineForLane]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[fnGetBurnupTrendLineForLane]
(
    @boardId BIGINT,
    @startLaneId BIGINT,
    @numberOfDaysBack INT,
    @numberOfDaysForward INT,
    @trendName NVARCHAR(50),
    @excludedLanesString NVARCHAR(max) = '',
    @includedTagsString NVARCHAR(max) = '',
    @excludedTagsString NVARCHAR(max) = '',
    @includedCardTypes NVARCHAR(max) = '',
    @includedClassOfServices NVARCHAR(max) = '',
    @offsetHours INT = 0
)

RETURNS
    @trendRows TABLE
    (
        TrendName NVARCHAR(50),
        MeasurementDate DATETIME,
        CardCountOnDate DECIMAL(19,10),
        CardSizeOnDate DECIMAL(19,10),
        DailyCountTrend DECIMAL(19,10),
        DailySizeTrend DECIMAL(19,10)
    )
AS

BEGIN

    DECLARE @lookBackDate DATETIME
    DECLARE @currentDate DATETIME
    DECLARE @lookForwardDate DATETIME
    DECLARE @lookBackCardCount INT
    DECLARE @lookBackCardSize INT
    DECLARE @currentCardCount INT
    DECLARE @currentCardSize INT
    DECLARE @projectForwardCardCount INT
    DECLARE @projectForwardCardSize INT
    DECLARE @cardCountPerDay DECIMAL(19,10)
    DECLARE @cardSizePerDay DECIMAL(19,10)
    DECLARE @progressDate DATETIME
    DECLARE @runningCountTotal DECIMAL(19,10)
    DECLARE @runningSizeTotal DECIMAL(19,10)
    DECLARE @useIncludeTagTable BIT
    DECLARE @useExcludeTagTable BIT

    SELECT  @lookBackDate = DATEADD(DAY, -@numberOfDaysBack, CONVERT(DATE, DATEADD(hour, ISNULL(@offsetHours, 30), GETUTCDATE()))) -- Default to 30 days back
          , @lookForwardDate = DATEADD(DAY, @numberOfDaysForward, CONVERT(DATE, DATEADD(hour, ISNULL(@offsetHours, 30), GETUTCDATE())))
          , @currentDate = CONVERT(DATE, DATEADD(hour, ISNULL(@offsetHours, 0) ,GETUTCDATE()))

    --Get all the Lanes underneath

    DECLARE @lanesBelow TABLE
    (
        LaneId BIGINT
    )

    INSERT INTO @lanesBelow
    SELECT DISTINCT LO.LaneId
    FROM [dbo].fnGetLaneOrder(@boardId) LO
    WHERE LO.LaneRank >= (SELECT LaneRank FROM [dbo].fnGetLaneOrder(@boardId) WHERE LaneID = @startLaneId)
    AND LO.LaneId NOT IN (SELECT LaneId FROM [dbo].[fnSplitLaneParameterString](@excludedLanesString)) -- Exclude the lanes

    DECLARE @cardWithIncludeTags TABLE
    (
        CardId BIGINT
    )

    DECLARE @cardWithExcludeTags TABLE
    (
        CardId BIGINT
    )

    SET @useIncludeTagTable = 0 

    --IF (NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL OR NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL)
    --BEGIN
    --    -- Refresh the card tag cache
    --    EXECUTE [dbo].[usp_RefreshBoardCardCache] @boardId, 1
    --END

    IF NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL
    BEGIN
        SET @useIncludeTagTable = 1

        INSERT INTO @cardWithIncludeTags
        SELECT [CardId]
        FROM [fnGetTagsList](@boardId,@includedTagsString)
    END

    SET @useExcludeTagTable = 0

    IF NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL
    BEGIN
        SET @useExcludeTagTable = 1

        INSERT INTO @cardWithExcludeTags
        SELECT [CardId]
        FROM [fnGetTagsList](@boardId,@excludedTagsString)
    END;

	SELECT DISTINCT
		@lookBackCardCount = COUNT(C.CardId),
		@lookBackCardSize = SUM(CASE WHEN C.Size IS NULL OR C.Size = 0 THEN 1 ELSE C.Size END)
	FROM [dbo].[fact_CardLaneContainmentPeriod] CP
	JOIN @lanesBelow LB ON LB.LaneID = CP.LaneId
	JOIN [dbo].[udtf_CurrentCards](@boardId) C ON C.CardId = CP.CardID
	JOIN [dbo].[fnGetDefaultCardTypes](@boardId, @includedCardTypes) CT ON CT.CardTypeId = C.TypeID
	LEFT JOIN [dbo].[fnGetDefaultClassesOfService](@boardId, @includedClassOfServices) COS ON NULLIF(COS.ClassOfServiceId,0) = C.ClassOfServiceID
	LEFT JOIN @cardWithIncludeTags IT ON IT.CardId = C.CardId
	LEFT JOIN @cardWithExcludeTags ET ON ET.CardId = C.CardId
	WHERE @lookBackDate BETWEEN DATEADD(hour, @offsetHours, CP.ContainmentStartDate) AND DATEADD(hour, @offsetHours, ISNULL(CP.ContainmentEndDate, GETUTCDATE()))
	AND CP.CardID = (CASE WHEN @useIncludeTagTable = 1 THEN IT.CardId ELSE CP.CardID END)
	AND ((@useExcludeTagTable = 1 AND ET.CardId IS NULL) OR @useExcludeTagTable = 0)

	SELECT DISTINCT
		@currentCardCount = COUNT(C.CardId),
		@currentCardSize = SUM(CASE WHEN C.Size IS NULL OR C.Size = 0 THEN 1 ELSE C.Size END)
	FROM [dbo].[fact_CardLaneContainmentPeriod] CP
	JOIN @lanesBelow LB ON LB.LaneID = CP.LaneId
	JOIN [dbo].[udtf_CurrentCards](@boardId) C ON C.CardId = CP.CardID
	JOIN [dbo].[fnGetDefaultCardTypes](@boardId, @includedCardTypes) CT ON CT.CardTypeId = C.TypeID
	LEFT JOIN [dbo].[fnGetDefaultClassesOfService](@boardId, @includedClassOfServices) COS ON NULLIF(COS.ClassOfServiceId,0) = C.ClassOfServiceID
	LEFT JOIN @cardWithIncludeTags IT ON IT.CardId = C.CardId
	LEFT JOIN @cardWithExcludeTags ET ON ET.CardId = C.CardId
	WHERE @currentDate BETWEEN DATEADD(hour, @offsetHours, CP.ContainmentStartDate) AND DATEADD(hour, @offsetHours, ISNULL(CP.ContainmentEndDate, GETUTCDATE()))
	AND CP.CardID = (CASE WHEN @useIncludeTagTable = 1 THEN IT.CardId ELSE CP.CardID END)
	AND ((@useExcludeTagTable = 1 AND ET.CardId IS NULL) OR @useExcludeTagTable = 0)

    -- Calculate the Number and Size per day
    SET @cardCountPerDay =  CONVERT(DECIMAL(19,10), (@currentCardCount - @lookBackCardCount)) / @numberOfDaysBack
    SET @cardSizePerDay = CONVERT(DECIMAL(19,10), (@currentCardSize - @lookBackCardSize)) / @numberOfDaysBack

    --Insert the Lookback row
    INSERT INTO @trendRows
    SELECT @trendName, @lookBackDate, @lookBackCardCount, @lookBackCardSize, @cardCountPerDay, @cardSizePerDay

    --insert the current row
    INSERT INTO @trendRows
    SELECT @trendName, @currentDate, @currentCardCount, @currentCardSize, @cardCountPerDay, @cardSizePerDay

    -- create a projection row for every day out to the future date
    SELECT @progressDate = DATEADD(DAY, 1, @currentDate), @runningCountTotal = @currentCardCount + @cardCountPerDay, @runningSizeTotal = @currentCardSize + @cardSizePerDay

    WHILE (@progressDate <= @lookForwardDate)
    BEGIN
        INSERT INTO @trendRows
        SELECT @trendName, @progressDate, @runningCountTotal, @runningSizeTotal, @cardCountPerDay, @cardSizePerDay

        SELECT @progressDate = DATEADD(DAY, 1, @progressDate), @runningCountTotal = @runningCountTotal + @cardCountPerDay, @runningSizeTotal = @runningSizeTotal + @cardSizePerDay
    END

    RETURN

END


GO
/****** Object:  UserDefinedFunction [dbo].[fnGetBurnupTrendLineForLane_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[fnGetBurnupTrendLineForLane_0_2]
(
    @boardId BIGINT,
    @startLaneId BIGINT,
    @numberOfDaysBack INT,
    @numberOfDaysForward INT,
    @trendName NVARCHAR(50),
    @excludedLanesString NVARCHAR(max) = '',
    @includedTagsString NVARCHAR(max) = '',
    @excludedTagsString NVARCHAR(max) = '',
    @includedCardTypes NVARCHAR(max) = '',
    @includedClassOfServices NVARCHAR(max) = '',
    @offsetHours INT = 0
)

RETURNS
    @trendRows TABLE
    (
        TrendName NVARCHAR(50),
        MeasurementDate DATETIME,
        CardCountOnDate DECIMAL(19,10),
        CardSizeOnDate DECIMAL(19,10),
        DailyCountTrend DECIMAL(19,10),
        DailySizeTrend DECIMAL(19,10)
    )
AS

BEGIN

    DECLARE @lookBackDate DATETIME
    DECLARE @currentDate DATETIME
    DECLARE @lookForwardDate DATETIME
    DECLARE @lookBackCardCount INT
    DECLARE @lookBackCardSize INT
    DECLARE @currentCardCount INT
    DECLARE @currentCardSize INT
    DECLARE @projectForwardCardCount INT
    DECLARE @projectForwardCardSize INT
    DECLARE @cardCountPerDay DECIMAL(19,10)
    DECLARE @cardSizePerDay DECIMAL(19,10)
    DECLARE @progressDate DATETIME
    DECLARE @runningCountTotal DECIMAL(19,10)
    DECLARE @runningSizeTotal DECIMAL(19,10)
    DECLARE @useIncludeTagTable BIT
    DECLARE @useExcludeTagTable BIT

    SELECT  @lookBackDate = DATEADD(DAY, -@numberOfDaysBack, CONVERT(DATE, DATEADD(hour, ISNULL(@offsetHours, 30), GETUTCDATE()))) -- Default to 30 days back
          , @lookForwardDate = DATEADD(DAY, @numberOfDaysForward, CONVERT(DATE, DATEADD(hour, ISNULL(@offsetHours, 30), GETUTCDATE())))
          , @currentDate = CONVERT(DATE, DATEADD(hour, ISNULL(@offsetHours, 0) ,GETUTCDATE()))

    --Get all the Lanes underneath

    DECLARE @lanesBelow TABLE
    (
        LaneId BIGINT
    )

    INSERT INTO @lanesBelow
    SELECT DISTINCT LO.LaneId
    FROM [dbo].[fnGetLaneOrder_0_2](@boardId) LO
    WHERE LO.LaneRank >= (SELECT LaneRank FROM [dbo].[fnGetLaneOrder_0_2](@boardId) WHERE LaneID = @startLaneId)
    AND LO.LaneId NOT IN (SELECT LaneId FROM [dbo].[fnSplitLaneParameterString_0_2](@excludedLanesString)) -- Exclude the lanes

    DECLARE @cardWithIncludeTags TABLE
    (
        CardId BIGINT
    )

    DECLARE @cardWithExcludeTags TABLE
    (
        CardId BIGINT
    )

    SET @useIncludeTagTable = 0

    IF NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL
    BEGIN
        SET @useIncludeTagTable = 1

        INSERT INTO @cardWithIncludeTags
        SELECT [CardId]
        FROM [fnGetTagsList_0_2](@boardId, @includedTagsString)
    END

    SET @useExcludeTagTable = 0

    IF NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL
    BEGIN
        SET @useExcludeTagTable = 1

        INSERT INTO @cardWithExcludeTags
        SELECT [CardId]
        FROM [fnGetTagsList_0_2](@boardId, @excludedTagsString)
    END;

	DECLARE @organizationId BIGINT = (SELECT TOP 1 [OrganizationId] FROM [dim_Board] WHERE [Id] = @boardId)

	SELECT DISTINCT
		@lookBackCardCount = COUNT(C.CardId),
		@lookBackCardSize = SUM(CASE WHEN C.Size IS NULL OR C.Size = 0 THEN 1 ELSE C.Size END)
	FROM [dbo].[fact_CardLaneContainmentPeriod] CP
	JOIN @lanesBelow LB ON LB.LaneID = CP.LaneId
	JOIN [dbo].[udtf_CurrentCards_0_2](@boardId) C ON C.CardId = CP.CardID
	JOIN [dbo].[fnGetDefaultCardTypes_0_2](@boardId, @includedCardTypes) CT ON CT.CardTypeId = C.TypeID
	LEFT JOIN [dbo].[fnGetDefaultClassesOfService_0_2](@boardId, @includedClassOfServices) COS ON NULLIF(COS.ClassOfServiceId,0) = C.ClassOfServiceID
	LEFT JOIN @cardWithIncludeTags IT ON IT.CardId = C.CardId
	LEFT JOIN @cardWithExcludeTags ET ON ET.CardId = C.CardId
	WHERE @lookBackDate BETWEEN DATEADD(hour, @offsetHours, CP.ContainmentStartDate) AND DATEADD(hour, @offsetHours, ISNULL(CP.ContainmentEndDate, GETUTCDATE()))
	AND CP.CardID = (CASE WHEN @useIncludeTagTable = 1 THEN IT.CardId ELSE CP.CardID END)
	AND ((@useExcludeTagTable = 1 AND ET.CardId IS NULL) OR @useExcludeTagTable = 0)

	SELECT DISTINCT
		@currentCardCount = COUNT(C.CardId),
		@currentCardSize = SUM(CASE WHEN C.Size IS NULL OR C.Size = 0 THEN 1 ELSE C.Size END)
	FROM [dbo].[fact_CardLaneContainmentPeriod] CP
	JOIN @lanesBelow LB ON LB.LaneID = CP.LaneId
	JOIN [dbo].[udtf_CurrentCards_0_2](@boardId) C ON C.CardId = CP.CardID
	JOIN [dbo].[fnGetDefaultCardTypes_0_2](@boardId, @includedCardTypes) CT ON CT.CardTypeId = C.TypeID
	LEFT JOIN [dbo].[fnGetDefaultClassesOfService_0_2](@boardId, @includedClassOfServices) COS ON NULLIF(COS.ClassOfServiceId,0) = C.ClassOfServiceID
	LEFT JOIN @cardWithIncludeTags IT ON IT.CardId = C.CardId
	LEFT JOIN @cardWithExcludeTags ET ON ET.CardId = C.CardId
	WHERE @currentDate BETWEEN DATEADD(hour, @offsetHours, CP.ContainmentStartDate) AND DATEADD(hour, @offsetHours, ISNULL(CP.ContainmentEndDate, GETUTCDATE()))
	AND CP.CardID = (CASE WHEN @useIncludeTagTable = 1 THEN IT.CardId ELSE CP.CardID END)
	AND ((@useExcludeTagTable = 1 AND ET.CardId IS NULL) OR @useExcludeTagTable = 0)

    -- Calculate the Number and Size per day
    SET @cardCountPerDay =  CONVERT(DECIMAL(19,10), (@currentCardCount - @lookBackCardCount)) / @numberOfDaysBack
    SET @cardSizePerDay = CONVERT(DECIMAL(19,10), (@currentCardSize - @lookBackCardSize)) / @numberOfDaysBack

    --Insert the Lookback row
    INSERT INTO @trendRows
    SELECT @trendName, @lookBackDate, @lookBackCardCount, @lookBackCardSize, @cardCountPerDay, @cardSizePerDay

    --insert the current row
    INSERT INTO @trendRows
    SELECT @trendName, @currentDate, @currentCardCount, @currentCardSize, @cardCountPerDay, @cardSizePerDay

    -- create a projection row for every day out to the future date
    SELECT @progressDate = DATEADD(DAY, 1, @currentDate), @runningCountTotal = @currentCardCount + @cardCountPerDay, @runningSizeTotal = @currentCardSize + @cardSizePerDay

    WHILE (@progressDate <= @lookForwardDate)
    BEGIN
        INSERT INTO @trendRows
        SELECT @trendName, @progressDate, @runningCountTotal, @runningSizeTotal, @cardCountPerDay, @cardSizePerDay

        SELECT @progressDate = DATEADD(DAY, 1, @progressDate), @runningCountTotal = @runningCountTotal + @cardCountPerDay, @runningSizeTotal = @runningSizeTotal + @cardSizePerDay
    END

    RETURN

END

GO
/****** Object:  UserDefinedFunction [dbo].[fnGetCalculatedBurnupTrajectory]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnGetCalculatedBurnupTrajectory] 
(
	@cardCountAtStart DECIMAL(19,10),
	@cardSizeAtStart DECIMAL(19,10),
	@cardCountAtEnd DECIMAL(19,10),
	@cardSizeAtEnd DECIMAL(19,10),
	@startDate DATETIME,
	@endDate DATETIME,
	@trendName NVARCHAR(50)
)
RETURNS 
	@trendRows TABLE 
	(
		TrendName NVARCHAR(50),
		MeasurementDate DATETIME,
		CardCountOnDate DECIMAL(19,10),
		CardSizeOnDate DECIMAL(19,10),
		DailyCountTrend DECIMAL(19,10),
		DailySizeTrend DECIMAL(19,10)
	)
AS
BEGIN
	
	DECLARE @cardsPerDay DECIMAL(19,10)
	DECLARE @sizePerday DECIMAL(19,10)
	DECLARE @progressDate DATETIME
	DECLARE @runningCountTotal DECIMAL(19,10)
	DECLARE @runningSizeTotal DECIMAL(19,10)

	SELECT @cardsPerDay = (@cardCountAtEnd - @cardCountAtStart) / DATEDIFF(DAY, @startDate, @endDate)
		  ,@sizePerday = (@cardSizeAtEnd - @cardSizeAtStart) / DATEDIFF(DAY, @startDate, @endDate)
		  ,@progressDate = @startDate
		  ,@runningCountTotal = @cardCountAtStart
		  ,@runningSizeTotal = @cardSizeAtStart

	WHILE (@progressDate <= @endDate)
	BEGIN
		INSERT INTO @trendRows
		SELECT 	@trendName, @progressDate, @runningCountTotal, @runningSizeTotal, @cardsPerDay, @sizePerday

		SELECT @progressDate = DATEADD(DAY, 1, @progressDate), @runningCountTotal = @runningCountTotal + @cardsPerDay, @runningSizeTotal = @runningSizeTotal + @sizePerday
	END 
	
	RETURN 
END



GO
/****** Object:  UserDefinedFunction [dbo].[fnGetCalculatedBurnupTrajectory_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO

CREATE FUNCTION [dbo].[fnGetCalculatedBurnupTrajectory_0_2] 
(
	@cardCountAtStart DECIMAL(19,10),
	@cardSizeAtStart DECIMAL(19,10),
	@cardCountAtEnd DECIMAL(19,10),
	@cardSizeAtEnd DECIMAL(19,10),
	@startDate DATETIME,
	@endDate DATETIME,
	@trendName NVARCHAR(50)
)
RETURNS 
	@trendRows TABLE 
	(
		TrendName NVARCHAR(50),
		MeasurementDate DATETIME,
		CardCountOnDate DECIMAL(19,10),
		CardSizeOnDate DECIMAL(19,10),
		DailyCountTrend DECIMAL(19,10),
		DailySizeTrend DECIMAL(19,10)
	)
AS
BEGIN
	
	DECLARE @cardsPerDay DECIMAL(19,10)
	DECLARE @sizePerday DECIMAL(19,10)
	DECLARE @progressDate DATETIME
	DECLARE @runningCountTotal DECIMAL(19,10)
	DECLARE @runningSizeTotal DECIMAL(19,10)

	SELECT @cardsPerDay = (@cardCountAtEnd - @cardCountAtStart) / DATEDIFF(DAY, @startDate, @endDate)
		  ,@sizePerday = (@cardSizeAtEnd - @cardSizeAtStart) / DATEDIFF(DAY, @startDate, @endDate)
		  ,@progressDate = @startDate
		  ,@runningCountTotal = @cardCountAtStart
		  ,@runningSizeTotal = @cardSizeAtStart

	WHILE (@progressDate <= @endDate)
	BEGIN
		INSERT INTO @trendRows
		SELECT 	@trendName, @progressDate, @runningCountTotal, @runningSizeTotal, @cardsPerDay, @sizePerday

		SELECT @progressDate = DATEADD(DAY, 1, @progressDate), @runningCountTotal = @runningCountTotal + @cardsPerDay, @runningSizeTotal = @runningSizeTotal + @sizePerday
	END 
	
	RETURN 
END

GO
/****** Object:  UserDefinedFunction [dbo].[fnGetDateTime]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnGetDateTime]
(
	@dateKey INT,
	@timeKey INT
)
RETURNS DATETIME
AS
BEGIN
	DECLARE @startDate DATETIME
	DECLARE @returnDate DATETIME
	SET @startDate = '12/31/2008' -- The date dimension starts at 1/1/2009

	SELECT @returnDate = DATEADD(second, @timeKey - 1, DATEADD(day, @dateKey, @startDate)) 

	-- Return the result of the function
	RETURN @returnDate

END 


GO
/****** Object:  UserDefinedFunction [dbo].[fnGetDefaultCardTypes]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[fnGetDefaultCardTypes] 
(
	@boardId BIGINT,
	@includedCardTypes NVARCHAR(MAX) = NULL
)
RETURNS 
@filterOnCardTypes TABLE 
(
	CardTypeId  BIGINT
)
AS
BEGIN

	--If card types are specified then we will return those.  
	IF (NULLIF(RTRIM(@includedCardTypes), '') IS NOT NULL)
	BEGIN
		INSERT INTO @filterOnCardTypes
		SELECT CT.CardTypeId FROM [dbo].[fnSplitCardTypeParameterString](@includedCardTypes) CT
	END
	ELSE
	BEGIN
		INSERT INTO @filterOnCardTypes
		SELECT DISTINCT cc.TypeId 
		FROM [dbo].[udtf_CurrentCards](@boardId) cc
	END
	
	RETURN 
END



GO
/****** Object:  UserDefinedFunction [dbo].[fnGetDefaultCardTypes_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO


CREATE FUNCTION [dbo].[fnGetDefaultCardTypes_0_2] 
(
	@boardId BIGINT,
	@includedCardTypes NVARCHAR(MAX) = NULL
)
RETURNS 
@filterOnCardTypes TABLE 
(
	CardTypeId  BIGINT
)
AS
BEGIN

	--If card types are specified then we will return those.  
	IF (NULLIF(RTRIM(@includedCardTypes), '') IS NOT NULL)
	BEGIN
		INSERT INTO @filterOnCardTypes
		SELECT CT.CardTypeId FROM [dbo].[fnSplitCardTypeParameterString_0_2](@includedCardTypes) CT
	END
	ELSE
	BEGIN
		INSERT INTO @filterOnCardTypes
		SELECT DISTINCT cc.TypeId 
		FROM [dbo].[udtf_CurrentCards_0_2](@boardId) cc
	END
	
	RETURN 
END

GO
/****** Object:  UserDefinedFunction [dbo].[fnGetDefaultClassesOfService]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[fnGetDefaultClassesOfService] 
(
	@boardId BIGINT,
	@includedClassOfServices NVARCHAR(MAX) = NULL
)
RETURNS 
@filterOnClassesOfService TABLE 
(
	ClassOfServiceId  BIGINT
)
AS
BEGIN

	--If COS are specified then we will return those.  
	IF (NULLIF(RTRIM(@includedClassOfServices),'') IS NOT NULL)
	BEGIN
		INSERT INTO @filterOnClassesOfService
		SELECT NULLIF(CS.ClassOfServiceId, 0) FROM [dbo].[fnSplitClassOfServiceParameterString](@includedClassOfServices) CS
	END
	ELSE
	BEGIN
		INSERT INTO @filterOnClassesOfService
		SELECT DISTINCT cc.ClassOfServiceId 
		FROM [dbo].[udtf_CurrentCards](@boardId) cc

	END
	
	RETURN 
END



GO
/****** Object:  UserDefinedFunction [dbo].[fnGetDefaultClassesOfService_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO


CREATE FUNCTION [dbo].[fnGetDefaultClassesOfService_0_2] 
(
	@boardId BIGINT,
	@includedClassOfServices NVARCHAR(MAX) = NULL
)
RETURNS 
@filterOnClassesOfService TABLE 
(
	ClassOfServiceId  BIGINT
)
AS
BEGIN

	DECLARE @organizationId BIGINT = (SELECT TOP 1 [OrganizationId] FROM [dim_Board] WHERE [Id] = @boardId)

	--If COS are specified then we will return those.  
	IF (NULLIF(RTRIM(@includedClassOfServices),'') IS NOT NULL)
	BEGIN
		INSERT INTO @filterOnClassesOfService
		SELECT NULLIF(CS.ClassOfServiceId, 0) FROM [dbo].[fnSplitClassOfServiceParameterString_0_2](@includedClassOfServices) CS
	END
	ELSE
	BEGIN
		INSERT INTO @filterOnClassesOfService
		SELECT DISTINCT cc.ClassOfServiceId 
		FROM [dbo].[udtf_CurrentCards_0_2](@boardId) cc

	END
	
	RETURN 
END

GO
/****** Object:  UserDefinedFunction [dbo].[fnGetFinishLanes]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnGetFinishLanes]
(
	@boardId BIGINT,
	@finishLanesString NVARCHAR(max) = ''
)
RETURNS
@finishLanes TABLE 
(
	LaneId BIGINT
)
AS
BEGIN
	INSERT INTO @finishLanes
		SELECT DISTINCT L.LaneId AS LaneId
		FROM [dbo].[udtf_CurrentLanes](@boardId) L
		JOIN [dbo].[fnSplitLaneParameterString](@finishLanesString) RL ON RL.LaneId = L.LaneId 

	--If the end lanes aren't specified, then default them to the Archive or Done-Done Lanes
	IF (@@ROWCOUNT = 0)
	BEGIN
		
		INSERT INTO @finishLanes
		SELECT DISTINCT L.LaneId AS LaneId
		FROM [dbo].[udtf_CurrentLanes](@boardId) L
		WHERE (
			L.LaneTypeId = 2
			OR L.LaneId IN (
						SELECT LaneId 
						FROM [dbo].[udtf_CurrentLanes](@boardId) L 
						WHERE L.IsDrillthroughDoneLane = 1 
						)
			)

		--PRINT 'Default Finish Lanes'
	END
	
	RETURN 
END



GO
/****** Object:  UserDefinedFunction [dbo].[fnGetFinishLanes_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[fnGetFinishLanes_0_2]
(
	@boardId BIGINT,
	@finishLanesString NVARCHAR(max) = ''
)
RETURNS
@finishLanes TABLE 
(
	[LaneId] BIGINT
)
AS
BEGIN
	INSERT INTO @finishLanes
		SELECT DISTINCT [L].[Id] AS [LaneId]
		FROM [dbo].[dim_Lane] [L]
		JOIN [dbo].[fnSplitLaneParameterString_0_2](@finishLanesString) [RL] ON [RL].[LaneId] = [L].[Id]
		WHERE
		[L].[ContainmentEndDate] IS NULL
		AND [L].[IsApproximate] = 0
		AND [L].[IsDeleted] = 0
		AND [L].[BoardId] = @boardId

	--If the end lanes aren't specified, then default them to the Archive or Done-Done Lanes
	IF (@@ROWCOUNT = 0)
	BEGIN
		
		INSERT INTO @finishLanes
		SELECT DISTINCT [L].[Id] AS [LaneId]
		FROM [dbo].[dim_Lane] [L]
		WHERE
		[L].[ContainmentEndDate] IS NULL
		AND [L].[IsApproximate] = 0
		AND [L].[IsDeleted] = 0
		AND [L].[BoardId] = @boardId
		AND
		(
			[L].[LaneTypeId] = 2
			OR [L].[IsDrillthroughDoneLane] = 1
		)
	END
	
	RETURN 
END

GO
/****** Object:  UserDefinedFunction [dbo].[fnGetLaneOrder]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO







CREATE FUNCTION [dbo].[fnGetLaneOrder] 
(	
	@boardId BIGINT
)
RETURNS 
 @laneOrder TABLE 
(
	LaneId BIGINT,
	LaneTitle NVARCHAR(255),
	LaneTypeId INT,
	ParentLaneId BIGINT,
	TopLevelOrder INT,
	LaneIndex INT,
	LaneLevel INT,
	PathString NVARCHAR(255),
	LaneRank INT,
	IsDoneLane BIT,
	IsArchiveLane BIT
)
AS
BEGIN

	DECLARE @paddingChar AS CHAR(1) = '0'
	DECLARE @numOfPaddedChars AS INT = 4

	;WITH LaneHierarchy ([Lane ID], [Lane Title], [Lane Type Id], [Parent Lane ID], [Index], [Lane Top Level Order], [Level], [Path], [IsDoneLane], [IsArchiveLane]) AS
	(
		SELECT 
			l.[LaneId] AS [Lane ID]
			, l.[Title] AS [Lane Title]
			, l.[LaneTypeId] AS [Lane Type ID]
			, l.[ParentLaneId] AS [Parent Lane ID]
			, l.[Index] + 1 AS [Index]
			, CASE l.[LaneTypeId]
				WHEN 1 THEN 1
				WHEN 0 THEN 2
				ELSE 3 END AS [Lane Top Level Order]
			, 1 as [Level]
			, CAST(RIGHT(REPLICATE(@paddingChar, @numOfPaddedChars) + CAST(l.[Index] AS VARCHAR), @numOfPaddedChars) AS VARCHAR(255)) AS [Path]
			, l.IsDrillthroughDoneLane AS IsDoneLane
			, CASE WHEN l.[LaneTypeId] = 2 THEN 1 ELSE 0 END AS [IsArchiveLane]
		FROM [udtf_CurrentLanes](@boardId) l
		WHERE l.[ParentLaneId] is NULL

		UNION ALL -- and now for the recursive part
    
		SELECT 
			l.[LaneId] AS [Lane ID]
			, l.[Title] AS [Lane Title]
			, l.[LaneTypeId] AS [Lane Type ID]
			, l.[ParentLaneID] AS [Parent Lane ID]
			, l.[Index] + 1 AS [Index]
			, CASE l.[LaneTypeId]
				WHEN 1 THEN 1
				WHEN 0 THEN 2
				ELSE 3 END AS [Lane Top Level Order]
			, lh.[Level] + 1 as [Level]
			, CAST(CONCAT(lh.[Path], RIGHT(REPLICATE(@paddingChar, @numOfPaddedChars) + LTRIM(RTRIM(CAST(l.[Index] AS VARCHAR))), @numOfPaddedChars)) AS VARCHAR(255)) AS [Path]
			, l.IsDrillthroughDoneLane AS IsDoneLane
			, CASE WHEN l.[LaneTypeId] = 2 THEN 1 ELSE 0 END AS [IsArchiveLane]
		FROM [udtf_CurrentLanes](@boardId) l
		INNER JOIN LaneHierarchy lh
		ON lh.[Lane ID] = l.[ParentLaneId]
		WHERE l.[ParentLaneId] IS NOT NULL
	)

	INSERT INTO @laneOrder
	SELECT [Lane ID], [Lane Title], [Lane Type ID], [Parent Lane ID], [Lane Top Level Order],[Index],[Level],[Path], RANK() OVER (ORDER BY [Lane Top Level Order], [Path], [Index]),[IsDoneLane], [IsArchiveLane]
	FROM LaneHierarchy
	ORDER BY [Lane Top Level Order], [Path], [Index]

	RETURN 
END




GO
/****** Object:  UserDefinedFunction [dbo].[fnGetLaneOrder_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO

CREATE FUNCTION [dbo].[fnGetLaneOrder_0_2] 
(	
	@boardId BIGINT
)
RETURNS 
 @laneOrder TABLE 
(
	[LaneId] BIGINT,
	[LaneTitle] NVARCHAR(255),
	[LaneTypeId] INT,
	[ParentLaneId] BIGINT,
	[TopLevelOrder] INT,
	[LaneIndex] INT,
	[LaneLevel] INT,
	[PathString] NVARCHAR(255),
	[LaneRank] INT,
	[IsDoneLane] BIT,
	[IsArchiveLane] BIT
)
AS
BEGIN

	DECLARE @paddingChar AS CHAR(1) = '0'
	DECLARE @numOfPaddedChars AS INT = 4

	;WITH LaneHierarchy ([Lane ID], [Lane Title], [Lane Type Id], [Parent Lane ID], [Index], [Lane Top Level Order], [Level], [Path], [IsDoneLane], [IsArchiveLane]) AS
	(
		SELECT 
			[L].[Id] AS [Lane ID]
			, [L].[Title] AS [Lane Title]
			, [L].[LaneTypeId] AS [Lane Type ID]
			, [L].[ParentLaneId] AS [Parent Lane ID]
			, [L].[Index] + 1 AS [Index]
			, CASE [L].[LaneTypeId]
				WHEN 1 THEN 1
				WHEN 0 THEN 2
				ELSE 3 END AS [Lane Top Level Order]
			, 1 as [Level]
			, CAST(RIGHT(REPLICATE(@paddingChar, @numOfPaddedChars) + CAST([L].[Index] AS VARCHAR), @numOfPaddedChars) AS VARCHAR(255)) AS [Path]
			, [L].IsDrillthroughDoneLane AS IsDoneLane
			, CASE WHEN [L].[LaneTypeId] = 2 THEN 1 ELSE 0 END AS [IsArchiveLane]
		FROM [dim_Lane] [L]
		WHERE 
		[L].[ParentLaneId] is NULL
		AND [L].[TaskBoardId] IS NULL
		AND [L].[ContainmentEndDate] IS NULL
		AND [L].[IsApproximate] = 0
		AND [L].[IsDeleted] = 0
		AND [L].[BoardId] = @boardId

		UNION ALL -- and now for the recursive part
    
		SELECT 
			[L].[Id] AS [Lane ID]
			, [L].[Title] AS [Lane Title]
			, [L].[LaneTypeId] AS [Lane Type ID]
			, [L].[ParentLaneID] AS [Parent Lane ID]
			, [L].[Index] + 1 AS [Index]
			, CASE [L].[LaneTypeId]
				WHEN 1 THEN 1
				WHEN 0 THEN 2
				ELSE 3 END AS [Lane Top Level Order]
			, [LH].[Level] + 1 as [Level]
			, CAST(CONCAT([LH].[Path], RIGHT(REPLICATE(@paddingChar, @numOfPaddedChars) + LTRIM(RTRIM(CAST([L].[Index] AS VARCHAR))), @numOfPaddedChars)) AS VARCHAR(255)) AS [Path]
			, [L].IsDrillthroughDoneLane AS IsDoneLane
			, CASE WHEN [L].[LaneTypeId] = 2 THEN 1 ELSE 0 END AS [IsArchiveLane]
		FROM [dim_Lane] [L]
		INNER JOIN LaneHierarchy [LH]
		ON [LH].[Lane ID] = [L].[ParentLaneId]
		WHERE
		[L].[ParentLaneId] IS NOT NULL
		AND [L].[TaskBoardId] IS NULL
		AND [L].[ContainmentEndDate] IS NULL
		AND [L].[IsApproximate] = 0
		AND [L].[IsDeleted] = 0
		AND [L].[BoardId] = @boardId
	)

	INSERT INTO @laneOrder
	SELECT [Lane ID], [Lane Title], [Lane Type ID], [Parent Lane ID], [Lane Top Level Order], [Index], [Level], [Path], RANK() OVER (ORDER BY [Lane Top Level Order], [Path], [Index]), [IsDoneLane], [IsArchiveLane]
	FROM [LaneHierarchy]
	ORDER BY [Lane Top Level Order], [Path], [Index]

	RETURN 
END


GO
/****** Object:  UserDefinedFunction [dbo].[fnGetMinimumDate]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[fnGetMinimumDate] 
(
	@boardId BIGINT,
	@offsetHours INT = 0 
)
RETURNS DATETIME
AS
BEGIN
	DECLARE @minDate DATETIME

	SELECT @minDate = MIN(DATEADD(hour, @offsetHours, CP.ContainmentStartDate))
		FROM [dbo].[fact_CardLaneContainmentPeriod] CP
		JOIN [dbo].[udtf_CurrentLanes](@boardId) L ON CP.LaneID = L.LaneId

	RETURN @minDate

END  


GO
/****** Object:  UserDefinedFunction [dbo].[fnGetStartLanes]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnGetStartLanes]
(
	@boardId BIGINT,
	@startLanesString NVARCHAR(max) = ''
)
RETURNS
@startLanes TABLE
(
	LaneId BIGINT
)
AS
BEGIN
	INSERT INTO @startLanes
		SELECT DISTINCT L.LaneId AS LaneId
		FROM [dbo].[udtf_CurrentLanes](@boardId) L
		JOIN [dbo].[fnSplitLaneParameterString](@startLanesString) RL ON RL.LaneId = L.LaneId 

	--If the start lanes aren't specified, then default them to the Backlog Lanes
	IF (@@ROWCOUNT = 0)
	BEGIN
		INSERT INTO @startLanes
		SELECT DISTINCT L.LaneId AS LaneId
		FROM [dbo].[udtf_CurrentLanes](@boardId) L
		WHERE L.LaneTypeId != 2
		AND L.LaneId NOT IN (
						SELECT LaneId 
						FROM [dbo].[udtf_CurrentLanes](@boardId) L 
						WHERE L.IsDrillthroughDoneLane = 1 
						)

	END
	
	RETURN 
END



GO
/****** Object:  UserDefinedFunction [dbo].[fnGetStartLanes_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[fnGetStartLanes_0_2]
(
	@boardId BIGINT,
	@startLanesString NVARCHAR(max) = ''
)
RETURNS
@startLanes TABLE
(
	[LaneId] BIGINT
)
AS
BEGIN
	INSERT INTO @startLanes
		SELECT DISTINCT [L].[Id] AS [LaneId]
		FROM [dbo].[dim_Lane] [L]
		JOIN [dbo].[fnSplitLaneParameterString_0_2](@startLanesString) [RL] ON [RL].[LaneId] = [L].[Id] 
		WHERE
		[L].[BoardId] = @boardId
		AND [L].[ContainmentEndDate] IS NULL
		AND [L].[IsApproximate] = 0
		AND [L].[IsDeleted] = 0

	--If the start lanes aren't specified, then default them to the Backlog Lanes
	IF (@@ROWCOUNT = 0)
	BEGIN
		INSERT INTO @startLanes
		SELECT DISTINCT [L].[Id] AS [LaneId]
		FROM [dbo].[dim_Lane] [L]
		WHERE
		[L].[BoardId] = @boardId
		AND [L].[ContainmentEndDate] IS NULL
		AND [L].[IsApproximate] = 0
		AND [L].[IsDeleted] = 0
		AND [L].[LaneTypeId] != 2
		AND ([L].[IsDrillthroughDoneLane] = 0 OR [L].[IsDrillthroughDoneLane] IS NULL)
	END
	
	RETURN 
END

GO
/****** Object:  UserDefinedFunction [dbo].[fnGetTagsList]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[fnGetTagsList]
(
	@boardId BIGINT,
	@tagsString NVARCHAR(max) = ''
)
RETURNS 
@cardsWithTags TABLE 
(
	CardId BIGINT
)
AS
BEGIN
	IF NULLIF(RTRIM(@tagsString),'') IS NOT NULL
		BEGIN

			INSERT INTO @cardsWithTags
			SELECT DISTINCT bct.[CardId]
			FROM [dbo].[_BoardCardTag] bct
			INNER JOIN [dbo].[_BoardTag] bt
				ON bct.[BoardTagId] = bt.[BoardTagId]
			INNER JOIN [dbo].[udtf_SplitString](@tagsString, N',') ss
				ON CHECKSUM(ss.[Value]) = bt.[cs_Tag]
			WHERE bt.[BoardId] = @boardId
			

			--INSERT INTO @cardsWithTags
			--SELECT [CardId]
			--FROM [dbo].[CardTags] CT
			--JOIN [dbo].[fnSplitTags](@tagsString) ST ON CT.[TagValue] = ST.TagValue
			--WHERE CT.BoardId = @boardId

		END
	
	RETURN 
END




GO
/****** Object:  UserDefinedFunction [dbo].[fnGetTagsList_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[fnGetTagsList_0_2]
(
	@boardId BIGINT,
	@tagsString NVARCHAR(max) = ''
)
RETURNS 
@cardsWithTags TABLE 
(
	[CardId] BIGINT
)
AS
BEGIN
	IF NULLIF(RTRIM(@tagsString),'') IS NOT NULL
		BEGIN

			INSERT INTO @cardsWithTags
			SELECT DISTINCT [BCT].[CardId]
			FROM [dbo].[_BoardCardTag] [BCT]
			INNER JOIN [dbo].[_BoardTag] [BT]
				ON bct.[BoardTagId] = [BT].[BoardTagId]
			INNER JOIN [dbo].[udtf_SplitString_0_2](@tagsString, N',') [ss]
				ON CHECKSUM([ss].[Value]) = [BT].[cs_Tag]
			WHERE [BT].[BoardId] = @boardId

		END
	RETURN 
END

GO
/****** Object:  UserDefinedFunction [dbo].[fnGetUserBoardRole]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[fnGetUserBoardRole]
(
	@boardId BIGINT,
	@userId BIGINT
)
RETURNS bit
WITH EXECUTE AS CALLER
AS
BEGIN

	DECLARE @hasAccess BIT
	DECLARE @isEnabled BIT
	DECLARE @isOrgAdmin BIT
	DECLARE @isAccountOwner BIT
	DECLARE @roleType INT
	DECLARE @isShared BIT
	DECLARE @sharedBoardRole BIT

	IF @userId = -1
		RETURN 0

	IF NOT EXISTS (SELECT [BoardId] FROM [dbo].[udtf_CurrentBoards](@boardId))
		RETURN 0

	IF NOT EXISTS (SELECT [UserId] FROM [dbo].[udtf_CurrentUser](@userId))
		RETURN 0

	SELECT 
		@isEnabled = cU.[IsEnabled]
		, @isOrgAdmin = cU.[IsOrgAdmin]
		, @isAccountOwner = cU.[IsAccountOwner]
	FROM [dbo].[udtf_CurrentUser](@userId) cU

	IF (@isOrgAdmin = 1 OR @isAccountOwner = 1)
		RETURN 1

	SELECT @roleType = [RoleTypeId] FROM [dbo].[udtf_CurrentBoardRole](@boardId, @userId)

	IF @roleType IS NOT NULL
	BEGIN
		IF @roleType > 0
			RETURN 1
		ELSE
			RETURN 0
	END
	
	SELECT
		@isShared = [IsShared]
		, @sharedBoardRole = [SharedBoardRole]
	FROM [dbo].[udtf_CurrentBoards](@boardId)

	IF @isShared = 1
	BEGIN
		IF @sharedBoardRole > 0
			RETURN 1
		ELSE
			RETURN 0
	END

	RETURN 0

END 


GO
/****** Object:  UserDefinedFunction [dbo].[fnGetUserBoardRole_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[fnGetUserBoardRole_0_2]
(
	@boardId BIGINT,
	@userId BIGINT
)
RETURNS bit
WITH EXECUTE AS CALLER
AS
BEGIN

	DECLARE @hasAccess BIT
	DECLARE @isEnabled BIT
	DECLARE @isOrgAdmin BIT
	DECLARE @isAccountOwner BIT
	DECLARE @roleType INT
	DECLARE @isShared BIT
	DECLARE @sharedBoardRole BIT

	IF @userId = -1
		RETURN 0

	IF NOT EXISTS (SELECT TOP 1 [Id] FROM [dim_Board] WITH (NOLOCK) WHERE [Id] = @boardId)
		RETURN 0

	IF NOT EXISTS (SELECT TOP 1 [Id] FROM [dim_User] WITH (NOLOCK) WHERE [Id] = @userId)
		RETURN 0

	SELECT 
		@isEnabled = cU.[IsEnabled]
		, @isOrgAdmin = cU.[IsOrgAdmin]
		, @isAccountOwner = cU.[IsAccountOwner]
	FROM [dbo].[udtf_CurrentUser_0_2](@userId) cU

	IF (@isOrgAdmin = 1 OR @isAccountOwner = 1)
		RETURN 1

	SELECT @roleType = [RoleTypeId] FROM [dbo].[udtf_CurrentBoardRole_0_2](@boardId, @userId)

	IF @roleType IS NOT NULL
	BEGIN
		IF @roleType > 0
			RETURN 1
		ELSE
			RETURN 0
	END
	
	SELECT
		@isShared = [IsShared]
		, @sharedBoardRole = [SharedBoardRole]
	FROM [dbo].[udtf_CurrentBoards_0_2](@boardId)


	IF @isShared = 1
	BEGIN
		IF @sharedBoardRole > 0
			RETURN 1
		ELSE
			RETURN 0
	END

	RETURN 0

END

GO
/****** Object:  UserDefinedFunction [dbo].[fnLib_GetBoardLanes]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnLib_GetBoardLanes](@boardId BIGINT) RETURNS @dimLaneRows TABLE
(
 DimRowId BIGINT, 
 Id BIGINT, 
 Title NVARCHAR(2048), 
 LaneTypeId INT, 
 [Type] INT, 
 [ParentLaneId] BIGINT, 
 BoardId BIGINT, 
 BoardTitle NVARCHAR(2048), 
 OrganizationId BIGINT NULL,
 TaskboardId BIGINT NULL
)
AS

BEGIN

DECLARE @dimBoardId BIGINT;

SET @dimBoardId = (SELECT TOP 1 DimRowId FROM dim_Board WHERE Id = @boardId AND ContainmentEndDate IS NULL ORDER BY DimRowId DESC);


INSERT INTO @dimLaneRows 
(
	DimRowId, 
	Id, 
	Title, 
	LaneTypeId, 
	[Type], 
	[ParentLaneId], 
	BoardId, 
	BoardTitle, 
	OrganizationId,
	TaskboardId
)
SELECT l.DimRowId, l.Id, l.Title, l.LaneTypeId, l.[Type], l.[ParentLaneId], l.BoardId, b.Title, b.OrganizationId, l.TaskBoardId
FROM dim_lane l
JOIN dim_Board b ON l.BoardId = b.Id
WHERE l.ContainmentEndDate IS NULL
AND l.BoardId = @boardId
AND b.ContainmentEndDate IS NULL
AND l.IsDeleted = 0
AND b.DimRowId = @dimBoardId;


-- weed out any rows in @dimLaneRows that have duplicate open containments

DELETE FROM @dimLaneRows WHERE DimRowId NOT IN 
(SELECT dlr.rowid_unique FROM
(SELECT Id, MAX(DimRowId) AS rowid_unique FROM @dimLaneRows GROUP BY Id) dlr);

RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[fnSplitCardTypeParameterString]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnSplitCardTypeParameterString] 
( 
    @CardTypeIdsString NVARCHAR(MAX)
) 
RETURNS @output TABLE(CardTypeId BIGINT) 
BEGIN 
	DECLARE @delimiter CHAR(1)
    DECLARE @start INT
	DECLARE @end INT
	
    SELECT 
	@start = 1,
	@delimiter = ',' ,
	@end = CHARINDEX(@delimiter, @CardTypeIdsString)
    WHILE @start < LEN(@CardTypeIdsString) + 1 BEGIN 
        IF @end = 0  
            SET @end = LEN(@CardTypeIdsString) + 1
       
        INSERT INTO @output (CardTypeId)  
        VALUES (CONVERT(BIGINT,LTRIM(RTRIM(SUBSTRING(@CardTypeIdsString, @start, @end - @start))))) 
        SET @start = @end + 1 
        SET @end = CHARINDEX(@delimiter, @CardTypeIdsString, @start)
        
    END 
    RETURN 
END




GO
/****** Object:  UserDefinedFunction [dbo].[fnSplitCardTypeParameterString_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[fnSplitCardTypeParameterString_0_2] 
( 
    @CardTypeIdsString NVARCHAR(MAX)
) 
RETURNS @output TABLE(CardTypeId BIGINT) 
BEGIN 
	DECLARE @delimiter CHAR(1)
    DECLARE @start INT
	DECLARE @end INT
	
    SELECT 
	@start = 1,
	@delimiter = ',' ,
	@end = CHARINDEX(@delimiter, @CardTypeIdsString)
    WHILE @start < LEN(@CardTypeIdsString) + 1 BEGIN 
        IF @end = 0  
            SET @end = LEN(@CardTypeIdsString) + 1
       
        INSERT INTO @output (CardTypeId)  
        VALUES (CONVERT(BIGINT,LTRIM(RTRIM(SUBSTRING(@CardTypeIdsString, @start, @end - @start))))) 
        SET @start = @end + 1 
        SET @end = CHARINDEX(@delimiter, @CardTypeIdsString, @start)
        
    END 
    RETURN 
END

GO
/****** Object:  UserDefinedFunction [dbo].[fnSplitClassOfServiceParameterString]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnSplitClassOfServiceParameterString] 
( 
    @ClassOfServiceIdsString NVARCHAR(MAX)
) 
RETURNS @output TABLE(ClassOfServiceId BIGINT) 
BEGIN 
	DECLARE @delimiter CHAR(1)
    DECLARE @start INT
	DECLARE @end INT
	
    SELECT
	@start = 1,
	@delimiter = ',' ,
	@end = CHARINDEX(@delimiter, @ClassOfServiceIdsString)
    WHILE @start < LEN(@ClassOfServiceIdsString) + 1 BEGIN 
        IF @end = 0  
            SET @end = LEN(@ClassOfServiceIdsString) + 1
       
        INSERT INTO @output (ClassOfServiceId)  
        VALUES (CONVERT(BIGINT,LTRIM(RTRIM(SUBSTRING(@ClassOfServiceIdsString, @start, @end - @start))))) 
        SET @start = @end + 1 
        SET @end = CHARINDEX(@delimiter, @ClassOfServiceIdsString, @start)
        
    END 
    RETURN 
END




GO
/****** Object:  UserDefinedFunction [dbo].[fnSplitClassOfServiceParameterString_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[fnSplitClassOfServiceParameterString_0_2] 
( 
    @ClassOfServiceIdsString NVARCHAR(MAX)
) 
RETURNS @output TABLE(ClassOfServiceId BIGINT) 
BEGIN 
	DECLARE @delimiter CHAR(1)
    DECLARE @start INT
	DECLARE @end INT
	
    SELECT
	@start = 1,
	@delimiter = ',' ,
	@end = CHARINDEX(@delimiter, @ClassOfServiceIdsString)
    WHILE @start < LEN(@ClassOfServiceIdsString) + 1 BEGIN 
        IF @end = 0  
            SET @end = LEN(@ClassOfServiceIdsString) + 1
       
        INSERT INTO @output (ClassOfServiceId)  
        VALUES (CONVERT(BIGINT,LTRIM(RTRIM(SUBSTRING(@ClassOfServiceIdsString, @start, @end - @start))))) 
        SET @start = @end + 1 
        SET @end = CHARINDEX(@delimiter, @ClassOfServiceIdsString, @start)
        
    END 
    RETURN 
END

GO
/****** Object:  UserDefinedFunction [dbo].[fnSplitLaneParameterString]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnSplitLaneParameterString] 
( 
    @LaneIdsString NVARCHAR(MAX)
) 
RETURNS @output TABLE(LaneId BIGINT) 
BEGIN 
	DECLARE @delimiter CHAR(1)
    DECLARE @start INT
	DECLARE @end INT
	
    SELECT
	@start = 1,
	@delimiter = ',' ,
	@end = CHARINDEX(@delimiter, @LaneIdsString)
    WHILE @start < LEN(@LaneIdsString) + 1 BEGIN 
        IF @end = 0  
            SET @end = LEN(@LaneIdsString) + 1
       
        INSERT INTO @output (LaneId)  
        VALUES (CONVERT(BIGINT,LTRIM(RTRIM(SUBSTRING(@LaneIdsString, @start, @end - @start))))) 
        SET @start = @end + 1 
        SET @end = CHARINDEX(@delimiter, @LaneIdsString, @start)
        
    END 
    RETURN 
END




GO
/****** Object:  UserDefinedFunction [dbo].[fnSplitLaneParameterString_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[fnSplitLaneParameterString_0_2] 
( 
    @LaneIdsString NVARCHAR(MAX)
) 
RETURNS @output TABLE(LaneId BIGINT) 
BEGIN 
	DECLARE @delimiter CHAR(1)
    DECLARE @start INT
	DECLARE @end INT
	
    SELECT
	@start = 1,
	@delimiter = ',' ,
	@end = CHARINDEX(@delimiter, @LaneIdsString)
    WHILE @start < LEN(@LaneIdsString) + 1 BEGIN 
        IF @end = 0  
            SET @end = LEN(@LaneIdsString) + 1
       
        INSERT INTO @output (LaneId)  
        VALUES (CONVERT(BIGINT,LTRIM(RTRIM(SUBSTRING(@LaneIdsString, @start, @end - @start))))) 
        SET @start = @end + 1 
        SET @end = CHARINDEX(@delimiter, @LaneIdsString, @start)
        
    END 
    RETURN 
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_AllCardBlockedPeriods_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[udtf_AllCardBlockedPeriods_0_2]
(
	@organizationId BIGINT
)
RETURNS
@currentBlockedCards TABLE
(
	[Card ID] BIGINT,
	[StartDateKey] BIGINT,
	[Duration Seconds] BIGINT,
	[Blocked From Date] DATETIME,
	[Blocked To Date] DATETIME,
	[Card Title] NVARCHAR(255),
	[Card Size] INT,
	[Card Priority] VARCHAR(10),
	[Custom Icon ID] BIGINT,
	[Card Type ID] BIGINT,
	[Board ID] BIGINT,
	[Blocked By User ID] BIGINT,
	[Unblocked By User ID] BIGINT,
	[Blocked Reason] NVARCHAR(1000),
	[Unblocked Reason] NVARCHAR(1000)
)
AS
BEGIN
	INSERT INTO @currentBlockedCards
	SELECT
	  [CB].[CardId] AS [Card ID]
	, [CB].[StartDateKey]
	, [CB].[DurationSeconds] AS [Duration Seconds]
	, [CB].[ContainmentStartDate] AS [Blocked From Date]
	, [CB].[ContainmentEndDate] AS [Blocked To Date]
	, [CC].[Title] AS [Card Title]
	, [CC].[Size] AS [Card Size]
	, (CASE [CC].[Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Card Priority]
	, [CC].[ClassofServiceId] AS [Custom Icon ID]
	, [CC].[TypeId] AS [Card Type ID]
	, [CC].[BoardId] AS [Board ID]
	, [CB].[StartUserId] AS [Blocked By User ID]
	, [CB].[EndUserId] AS [Unblocked By User ID]
	, (
		SELECT TOP 1 [BlockReason] 
		FROM [dim_Card] [BC] 
		WHERE
		[BC].[Id] = [CC].[CardId] 
		AND [BC].[ContainmentStartDate] 
			BETWEEN [CB].[ContainmentStartDate] 
			AND ISNULL([CB].[ContainmentEndDate], GETUTCDATE())
		AND [BC].[IsBlocked] = 1
		ORDER BY [ContainmentStartDate] DESC
	  ) AS [Blocked Reason]
	  , (
		SELECT TOP 1 [BlockReason] 
		FROM [dim_Card] [BC] 
		WHERE
		[BC].[Id] = [CC].[CardId] 
		AND [BC].[ContainmentStartDate] 
			BETWEEN [CB].[ContainmentStartDate] 
			AND ISNULL([CB].[ContainmentEndDate], GETUTCDATE())
		AND [BC].[IsBlocked] = 0
		ORDER BY [ContainmentStartDate] DESC
	  ) AS [Unblocked Reason]

	FROM [fact_CardBlockContainmentPeriod] [CB]
	JOIN [udtf_CurrentCardsInOrg_0_2](@organizationId) [CC] ON [CC].[CardId] = [CB].[CardID]
	RETURN

END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_AllUserAssignments_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[udtf_AllUserAssignments_0_2]
(
	@organizationId BIGINT
)
RETURNS
@currentUserAssignments TABLE
(
	[DimRowId] BIGINT,
	[Card Id] BIGINT,
	[Card Title] NVARCHAR(255),
	[Card Size] INT,
	[Card Priority] INT,
	[Card Class of Service Id] BIGINT,
	[Card Type Id] BIGINT,
	[Assigned To User Id] BIGINT,
	[Assigned To User Email] NVARCHAR(255),
	[Assigned To User Name] NVARCHAR(255),
	[Assigned By User Id] BIGINT,
	[Unassigned By User Id] BIGINT,
	[Start Date Key] BIGINT,
	[Containment Start Date] DATETIME,
	[Containment End Date] DATETIME,
	[Duration (Seconds)] BIGINT,
	[Total Duration (Days)] BIGINT,
	[Total Duration (Hours)] BIGINT,
	[Total Duration (Days Minus Weekends)] BIGINT,
	[Board Id] BIGINT
)
AS
BEGIN
	INSERT INTO @currentUserAssignments
	SELECT
	[DimRowId],
	[CC].[CardId] AS [Card Id],
	[CC].[Title] AS [Card Title],
	[CC].[Size] AS [Card Size],
	[CC].[Priority] AS [Card Priority],
	[CC].[ClassOfServiceId] AS [Card Class of Service Id],
	[CC].[TypeId] AS [Card Type Id],
	[UA].[ToUserID] AS [Assigned To User Id],
	[UA].[ToUserEmail] AS [Assigned To User Email],
	[UA].[ToUserName] AS [Assigned To User Name],
	[UA].[StartUserId] AS [Assigned By User Id],
	[UA].[EndUserId] AS [Unassigned By User Id],
	[UA].[StartDateKey] AS [Start Date Key],
	[UA].[ContainmentStartDate] AS [Containment Start Date],
	[UA].[ContainmentEndDate] AS [Containment End Date],
	[UA].[DurationSeconds] AS [Duration (Seconds)],
	DATEDIFF(DAY,[UA].[ContainmentStartDate],ISNULL([UA].[ContainmentEndDate],GETUTCDATE())) AS [Total Duration (Days)],
	DATEDIFF(HOUR,[UA].[ContainmentStartDate],ISNULL([UA].[ContainmentEndDate],GETUTCDATE())) AS [Total Duration (Hours)],
	DATEDIFF(DAY, [UA].[ContainmentStartDate], ISNULL([UA].[ContainmentEndDate],GETUTCDATE())) - (DATEDIFF(WEEK, [UA].[ContainmentStartDate], ISNULL([UA].[ContainmentEndDate],GETUTCDATE())) * 2) - 
		CASE WHEN DATEPART(dw, [UA].[ContainmentStartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,ISNULL([UA].[ContainmentEndDate],GETUTCDATE())) = 1 THEN 1 ELSE 0 END [Total Duration (Days Minus Weekends)],
	[CC].[BoardId] AS [Board Id]
	FROM
	[fact_UserAssignmentContainmentPeriod] [UA]
	JOIN [udtf_CurrentCardsInOrg_0_2](@organizationId) [CC] ON [CC].[CardId] = [UA].[CardId]
	WHERE
	[UA].[IsApproximate] = 0
	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_ConnectionStats_byParentCardId]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Chris Gundersen
-- Create date: 25-Jul-2016
-- Description:	Gets the connection stats info
--				for a parent card and its children
-- =============================================
CREATE FUNCTION [dbo].[udtf_ConnectionStats_byParentCardId] 
(
	@parentCardId BIGINT
)
RETURNS @connectionStats TABLE 
(
	[Id] BIGINT
	, [IsBlocked] BIT
	, [Size] INT NULL
	, [PlannedStart] DATETIME NULL
	, [PlannedFinish] DATETIME NULL
	, [ActualStart] DATETIME NULL
	, [ActualFinish] DATETIME NULL
	, [TotalChildCount] INT
	, [StartedCount] INT
	, [NotStartedCount] INT
	, [CompletedCount] INT
	, [TotalChildSize] BIGINT
	, [TotalChildStartedSize] BIGINT
	, [TotalChildNotStartedSize] BIGINT
	, [TotalChildCompletedSize] BIGINT
	, [ChildProgressPercentageBySize] INT  -- Look at this
	, [BlockedChildCount] INT
	, [PastDueChildCount] INT
	, [EarliestPlannedStartOfChildren] DATETIME NULL
	, [LatestPlannedFinishOfChildren] DATETIME NULL
	, [EarliestActualStartOfChildren] DATETIME NULL
	, [LatestActualFinishOfChildren] DATETIME NULL -- Only set if all cards are finished
)
AS
BEGIN

	DECLARE @parentCardDimRowId BIGINT

	SELECT @parentCardDimRowId =  MAX(dC.[DimRowId])
	FROM [dbo].[dim_Card] dC
	WHERE [Id] = @parentCardId
	AND dC.[ContainmentEndDate] IS NULL
	AND dC.[IsApproximate] = 0
	AND dC.[IsDeleted] = 0
	
	INSERT INTO @connectionStats ([Id], [IsBlocked], [Size], [PlannedStart], [PlannedFinish], [ActualStart], [ActualFinish])
	SELECT
		dC.[Id] AS [Id]
		, dC.[IsBlocked] AS [IsBlocked]
		, ISNULL(dC.[Size], 0) AS [Size]
		, dC.[StartDate] AS [PlannedStart]
		, dC.[DueDate] AS [PlannedFinish]
		, dC.[ActualStartDate] AS [ActualStart]
		, dC.[ActualFinishDate] AS [ActualFinish]
	FROM [dbo].[dim_Card] dC
	WHERE dC.[DimRowId] = @parentCardDimRowId

	DECLARE @childCardDimRowIds TABLE ([ChildCardDimRowId] BIGINT)

	INSERT INTO @childCardDimRowIds
	SELECT MAX(dC.[DimRowId])
	FROM [dbo].[dim_Card] dC
	WHERE dC.[ParentCardId] = @parentCardId
	AND dC.[IsDeleted] = 0
	AND dC.[IsApproximate] = 0
	AND dC.[ContainmentEndDate] IS NULL
	GROUP BY dC.[Id]

	DECLARE @childCardData TABLE ([DimRowId] BIGINT, [Size] INT, [IsBlocked] BIT, [IsPastDue] BIT, [PlannedStart] DATETIME NULL, [PlannedFinish] DATETIME NULL, [ActualStart] DATETIME NULL, [ActualFinish] DATETIME NULL)

	INSERT INTO @childCardData
	SELECT
		dr.[ChildCardDimRowId]
		, ISNULL(dC.[Size], 0)
		, dC.[IsBlocked]
		, CASE
			WHEN dC.[DueDate] IS NULL OR dC.[ActualFinishDate] IS NULL THEN 0
			ELSE IIF(DATEDIFF(MILLISECOND, dC.[DueDate], dC.[ActualFinishDate]) > 0, 1, 0)
			END
		, dC.[StartDate]
		, dC.[DueDate]
		, dC.[ActualStartDate]
		, dC.[ActualFinishDate]
	FROM @childCardDimRowIds dr
	INNER JOIN [dbo].[dim_Card] dC
		ON dr.[ChildCardDimRowId] = dC.[DimRowId]

	DECLARE @allCardsComplete BIT = 0

	IF (SELECT COUNT(0) FROM @childCardData) = (SELECT COUNT(0) FROM @childCardData WHERE [ActualFinish] IS NOT NULL)
		SET @allCardsComplete = 1

	UPDATE @connectionStats
	SET 
		[TotalChildCount] = (SELECT ISNULL(COUNT(0), 0) FROM @childCardData)
		, [StartedCount] = (SELECT ISNULL(COUNT(0), 0) FROM @childCardData WHERE [ActualStart] IS NOT NULL AND [ActualFinish] IS NULL)
		, [NotStartedCount] = (SELECT ISNULL(COUNT(0), 0) FROM @childCardData WHERE [ActualStart] IS NULL)
		, [CompletedCount] = (SELECT ISNULL(COUNT(0), 0) FROM @childCardData WHERE [ActualFinish] IS NOT NULL)
		, [TotalChildSize] = (SELECT ISNULL(SUM([Size]), 0) FROM @childCardData)
		, [TotalChildStartedSize] = (SELECT ISNULL(SUM([Size]), 0) FROM @childCardData WHERE [ActualStart] IS NOT NULL AND [ActualFinish] IS NULL)
		, [TotalChildNotStartedSize] = (SELECT ISNULL(SUM([Size]), 0) FROM @childCardData WHERE [ActualStart] IS NULL)
		, [TotalChildCompletedSize] = (SELECT ISNULL(SUM([Size]), 0) FROM @childCardData WHERE [ActualFinish] IS NOT NULL)
		, [ChildProgressPercentageBySize] = 0
		, [BlockedChildCount] = (SELECT ISNULL(COUNT(0), 0) FROM @childCardData WHERE [IsBlocked] = 1)
		, [PastDueChildCount] = (SELECT ISNULL(COUNT(0), 0) FROM @childCardData WHERE [IsPastDue] = 1)
		, [EarliestPlannedStartOfChildren] = (SELECT MIN([PlannedStart]) FROM @childCardData WHERE [PlannedStart] IS NOT NULL)
		, [LatestPlannedFinishOfChildren] = (SELECT MAX([PlannedFinish]) FROM @childCardData WHERE [PlannedFinish] IS NOT NULL)
		, [EarliestActualStartOfChildren] = (SELECT MIN([ActualStart]) FROM @childCardData WHERE [ActualStart] IS NOT NULL)
		, [LatestActualFinishOfChildren] = IIF(@allCardsComplete = 1, (SELECT MAX([ActualFinish]) FROM @childCardData WHERE [ActualFinish] IS NOT NULL), NULL)
	
	RETURN 
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentBoardRole]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[udtf_CurrentBoardRole] 
(
	@boardId BIGINT,
	@userId	BIGINT
)
RETURNS @currentBoardRole TABLE 
(
	DimRowId	BIGINT,
	UserId		BIGINT,
	BoardId		BIGINT,
	RoleTypeId	INT
)
AS
BEGIN

	INSERT INTO @currentBoardRole
	SELECT
		MAX(br.[DimRowId]), br.[UserId], br.[BoardId], br.[RoleTypeId]
	FROM [dbo].[dim_BoardRole] br WITH (NOLOCK)
	WHERE br.[UserId] = @userId
	AND br.[BoardId] = @boardId
	AND br.[ContainmentEndDate] IS NULL
	AND br.[IsApproximate] = 0
	AND (br.[IsDeleted] = 0 OR br.[IsDeleted] IS NULL)
	GROUP BY br.[UserId], br.[BoardId], br.[RoleTypeId]

	RETURN
END


GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentBoardRole_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[udtf_CurrentBoardRole_0_2] 
(
	@boardId BIGINT,
	@userId	BIGINT
)
RETURNS @currentBoardRole TABLE 
(
	[DimRowId] BIGINT,
	[UserId] BIGINT,
	[BoardId] BIGINT,
	[RoleTypeId] INT
)
AS
BEGIN

	INSERT INTO @currentBoardRole
	SELECT
	MAX([BR].[DimRowId])
	,[BR].[UserId]
	,[BR].[BoardId]
	,[BR].[RoleTypeId]
	FROM [dbo].[dim_BoardRole] [BR] WITH (NOLOCK)
	WHERE
	[BR].[UserId] = @userId
	AND [BR].[BoardId] = @boardId
	AND [BR].[ContainmentEndDate] IS NULL
	AND [BR].[IsApproximate] = 0
	AND ([BR].[IsDeleted] = 0 OR [BR].[IsDeleted] IS NULL)
	GROUP BY [BR].[UserId], [BR].[BoardId], [BR].[RoleTypeId]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentBoards]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



-- =============================================
-- Author:		Chris Gundersen
-- Create date: 06-Apr-2015
-- Description:	Designed to get the current list of lanes for a board ID
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentBoards] 
(	
	@boardId	BIGINT
)
RETURNS @currentBoards TABLE 
(
	DimRowId	BIGINT,
	BoardId		BIGINT,
	OrgId		BIGINT,
	IsShared	BIT,
	SharedBoardRole INT
)
AS
BEGIN

	INSERT INTO @currentBoards
	SELECT
		MAX(b.[DimRowId]), b.[Id] AS [BoardId], b.[OrganizationId] AS [OrgId], b.[IsShared], b.[SharedBoardRole]
	FROM [dbo].[dim_Board] b WITH (NOLOCK)
	WHERE b.[Id] = @boardId
	AND b.[ContainmentEndDate] IS NULL
	AND b.[IsApproximate] = 0
	AND b.[IsDeleted] = 0
	AND b.[IsArchived] = 0
	GROUP BY b.[Id], b.[OrganizationId], b.[IsShared], b.[SharedBoardRole]

	RETURN
END


GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentBoards_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the newest row in dim_Board for the given Board Id
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentBoards_0_2] 
(	
	@boardId	BIGINT
)
RETURNS @currentBoards TABLE 
(
	[DimRowId] BIGINT,
	[BoardId] BIGINT,
	[OrganizationId] BIGINT,
	[IsShared] BIT,
	[SharedBoardRole] INT,
	[Title] NVARCHAR(255)
)
AS
BEGIN

	INSERT INTO @currentBoards
	SELECT
	TOP 1 
	[B].[DimRowId]
	,[B].[Id] AS [BoardId]
	,[B].[OrganizationId] AS [OrganizationId]
	,[B].[IsShared]
	,[B].[SharedBoardRole]
	,[B].[Title]
	FROM [dbo].[dim_Board] [B] WITH (NOLOCK)
	WHERE
	[B].[Id] = @boardId
	AND [B].[ContainmentEndDate] IS NULL
	AND [B].[IsApproximate] = 0
	AND [B].[IsDeleted] = 0
	AND [B].[IsArchived] = 0
	ORDER BY [B].[ContainmentStartDate] DESC

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentBoardsInOrg_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the newest rows in dim_Board for all boards for a given Organization Id
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentBoardsInOrg_0_2] 
(	
	@organizationId	BIGINT
)
RETURNS @currentBoards TABLE 
(
	[DimRowId] BIGINT,
	[BoardId] BIGINT,
	[OrganizationId] BIGINT,
	[IsShared] BIT,
	[SharedBoardRole] INT,
	[Title] NVARCHAR(255)
)
AS
BEGIN

	INSERT INTO @currentBoards
	SELECT
	MAX([B].[DimRowId])
	,[B].[Id] AS [BoardId]
	,[B].[OrganizationId] AS [OrganizationId]
	,[B].[IsShared]
	,[B].[SharedBoardRole]
	,[B].[Title]
	FROM [dbo].[dim_Board] [B] WITH (NOLOCK)
	WHERE
	[B].[OrganizationId] = @organizationId
	AND [B].[ContainmentEndDate] IS NULL
	AND [B].[IsApproximate] = 0
	AND [B].[IsDeleted] = 0
	AND [B].[IsArchived] = 0
	GROUP BY [B].[Id], [B].[OrganizationId], [B].[IsShared], [B].[SharedBoardRole], [B].[Title]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentCards]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



-- =============================================
-- Author:		Chris Gundersen
-- Create date: 06-Apr-2015
-- Description:	Designed to get the current list of lanes for a board ID
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentCards] 
(	
	@boardId	BIGINT
)
RETURNS @currentCards TABLE 
(
	DimRowId			BIGINT,
	BoardId				BIGINT,
	LaneId				BIGINT,
	CardId				BIGINT,
	Size				INT,
	TypeId				BIGINT,
	ClassOfServiceId	BIGINT,
	[Priority]			INT,
	[Title]				NVARCHAR(255)
)
AS
BEGIN

	INSERT INTO @currentCards
	SELECT
		MAX(c.[DimRowId]), cl.[BoardId], cl.[LaneId], c.[Id] AS [CardId], c.[Size], c.[TypeId], c.[ClassOfServiceId], c.[Priority], c.[Title]
	FROM [dbo].[dim_Card] c WITH (NOLOCK)
	INNER JOIN [dbo].[udtf_CurrentLanes](@boardId) cl
		ON c.[LaneId] = cl.[LaneId]
	WHERE c.[ContainmentEndDate] IS NULL
	AND c.[IsApproximate] = 0
	AND c.[IsDeleted] = 0
	GROUP BY cl.[BoardId], cl.[LaneId], c.[Id], c.[Size], c.[TypeId], c.[ClassOfServiceId], c.[Priority], c.[Title]

	RETURN
END





GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentCards_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the current list of cards for a given Board Id
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentCards_0_2] 
(	
	@boardId BIGINT
)
RETURNS @currentCards TABLE 
(
	[DimRowId] BIGINT,
	[BoardId] BIGINT,
	[LaneId] BIGINT,
	[CardId] BIGINT,
	[Size] INT,
	[TypeId] BIGINT,
	[ClassOfServiceId] BIGINT,
	[Priority] INT,
	[Title] NVARCHAR(255),
	[BlockReason] NVARCHAR(255)
)
AS
BEGIN

	INSERT INTO @currentCards
	SELECT
	MAX([C].[DimRowId])
	,[CL].[BoardId]
	,[CL].[LaneId]
	,[C].[Id] AS [CardId]
	,[C].[Size]
	,[C].[TypeId]
	,[C].[ClassOfServiceId]
	,[C].[Priority]
	,[C].[Title]
	,[C].[BlockReason]
	FROM [dbo].[dim_Card] [C] WITH (NOLOCK)
	INNER JOIN [dbo].[udtf_CurrentLanes_0_2](@boardId) [CL]
		ON [C].[LaneId] = [CL].[LaneId]
	WHERE [C].[ContainmentEndDate] IS NULL
	AND [C].[IsApproximate] = 0
	AND [C].[IsDeleted] = 0
	AND [CL].[BoardId] = @boardId
	GROUP BY [CL].[BoardId], [CL].[LaneId], [C].[Id], [C].[Size], [C].[TypeId], [C].[ClassOfServiceId], [C].[Priority], [C].[Title], [C].[BlockReason]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentCards_0_3]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO

-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the current list of cards for a given Board Id
-- =============================================
create FUNCTION [dbo].[udtf_CurrentCards_0_3] 
(	
	@boardId BIGINT
)
RETURNS @currentCards TABLE 
(
	[DimRowId] BIGINT,
	[BoardId] BIGINT,
	[LaneId] BIGINT,
	[CardId] BIGINT,
	[Size] INT,
	[TypeId] BIGINT,
	[ClassOfServiceId] BIGINT,
	[Priority] INT,
	[Title] NVARCHAR(255),
	[BlockReason] NVARCHAR(255),
	[ContainmentStartDate] datetime not null
)
AS
BEGIN

	INSERT INTO @currentCards
	SELECT
	MAX([C].[DimRowId])
	,[CL].[BoardId]
	,[CL].[LaneId]
	,[C].[Id] AS [CardId]
	,[C].[Size]
	,[C].[TypeId]
	,[C].[ClassOfServiceId]
	,[C].[Priority]
	,[C].[Title]
	,[C].[BlockReason]
	,[C].[ContainmentStartDate]
	FROM [dbo].[dim_Card] [C] WITH (NOLOCK)
	INNER JOIN [dbo].[udtf_CurrentLanes_0_2](@boardId) [CL]
		ON [C].[LaneId] = [CL].[LaneId]
	WHERE [C].[ContainmentEndDate] IS NULL
	AND [C].[IsApproximate] = 0
	AND [C].[IsDeleted] = 0
	AND [CL].[BoardId] = @boardId
	GROUP BY [CL].[BoardId], [CL].[LaneId], [C].[Id], [C].[Size], [C].[TypeId], [C].[ClassOfServiceId], [C].[Priority], [C].[Title], [C].[BlockReason],[C].[ContainmentStartDate]

	RETURN
END


GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentCards_0_5]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO


-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the current list of cards for a given Board Id
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentCards_0_5] 
(	
	@boardId BIGINT
)
RETURNS @currentCards TABLE 
(
	[DimRowId] BIGINT,
	[BoardId] BIGINT,
	[LaneId] BIGINT,
	[CardId] BIGINT,
	[Size] INT,
	[TypeId] BIGINT,
	[ClassOfServiceId] BIGINT,
	[Priority] INT,
	[Title] NVARCHAR(255),
	[BlockReason] NVARCHAR(255),
	[ContainmentStartDate] DATETIME NOT NULL
)
AS
BEGIN
	INSERT INTO @currentCards
	SELECT
	--MAX(),
	[C].[DimRowId],
	[CL].[BoardId]
	,[CL].[LaneId]
	,[C].[Id] AS [CardId]
	,[C].[Size]
	,[C].[TypeId]
	,[C].[ClassOfServiceId]
	,[C].[Priority]
	,[C].[Title]
	,[C].[BlockReason]
	,[C].[ContainmentStartDate]

	FROM [dbo].[dim_Card] [C]
	INNER JOIN 
	(SELECT MAX([CardDim].ContainmentStartDate) AS maxdim, [CardDim].[Id] AS [CardId] FROM
                            [dbo].[dim_card] [CardDim] WITH (NOLOCK)
							JOIN [dbo].dim_Lane [LN] ON [CardDim].LaneId = [LN].Id
							WHERE [LN].ContainmentEndDate IS NULL
                            GROUP BY [CardDim].[Id]) dup --where [C].ContainmentStartDate = dup.maxdim
                            ON [C].Id = dup.CardId AND [C].ContainmentStartDate = 
							dup.maxdim

	INNER JOIN [dbo].[udtf_CurrentLanes_0_2](@boardId) [CL]
		ON [C].[LaneId] = [CL].[LaneId]
	WHERE [C].[ContainmentEndDate] IS NULL
	AND [C].[IsApproximate] = 0
	AND [C].[IsDeleted] = 0
	AND [CL].[BoardId] = @boardId
	--GROUP BY [CL].[BoardId], [CL].[LaneId], [C].[Id], [C].[Size], [C].[TypeId], [C].[ClassOfServiceId], [C].[Priority], [C].[Title], [C].[BlockReason],[C].[ContainmentStartDate]

	RETURN
END



GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentCardsInOrg_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the current list of cards for a given Organization Id
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentCardsInOrg_0_2] 
(	
	@organizationId BIGINT
)
RETURNS @currentCards TABLE 
(
	[DimRowId] BIGINT,
	[BoardId] BIGINT,
	[LaneId] BIGINT,
	[CardId] BIGINT,
	[Size] INT,
	[TypeId] BIGINT,
	[ClassOfServiceId] BIGINT,
	[Priority] INT,
	[Title] NVARCHAR(255),
	[BlockReason] NVARCHAR(255)
)
AS
BEGIN

	INSERT INTO @currentCards
	SELECT
	MAX([C].[DimRowId])
	,[CL].[BoardId]
	,[CL].[LaneId]
	,[C].[Id] AS [CardId]
	,[C].[Size]
	,[C].[TypeId]
	,[C].[ClassOfServiceId]
	,[C].[Priority]
	,[C].[Title]
	,[C].[BlockReason]
	FROM [dbo].[dim_Card] [C] WITH (NOLOCK)
	INNER JOIN [dbo].[udtf_CurrentLanesInOrg_0_2](@organizationId) [CL]
		ON [C].[LaneId] = [CL].[LaneId]
	WHERE [C].[ContainmentEndDate] IS NULL
	AND [C].[IsApproximate] = 0
	AND [C].[IsDeleted] = 0
	GROUP BY [CL].[BoardId], [CL].[LaneId], [C].[Id], [C].[Size], [C].[TypeId], [C].[ClassOfServiceId], [C].[Priority], [C].[Title], [C].[BlockReason]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentCardTypes]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[udtf_CurrentCardTypes] 
(	
	@boardId	BIGINT
)
RETURNS @currentCardTypes TABLE 
(
	DimRowId			BIGINT,
	CardTypeId			BIGINT,
	Name				NVARCHAR(64)
)
AS
BEGIN

	INSERT INTO @currentCardTypes
	SELECT
		MAX(ct.[DimRowId]), ct.[Id] AS [CardTypeId], ct.[Name]
	FROM [dbo].[dim_CardTypes] ct WITH (NOLOCK)
	WHERE ct.[ContainmentEndDate] IS NULL
	AND ct.[IsApproximate] = 0
	AND (ct.[IsDeleted] = 0 OR ct.[IsDeleted] IS NULL)
	AND ct.[BoardId] = @boardId
	GROUP BY ct.[Id], ct.[Name]

	RETURN
END


GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentCardTypes_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the current list of card types for a given Board Id
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentCardTypes_0_2] 
(	
	@boardId BIGINT
)
RETURNS @currentCardTypes TABLE 
(
	[DimRowId] BIGINT,
	[CardTypeId] BIGINT,
	[Name] NVARCHAR(64)
)
AS
BEGIN

	INSERT INTO @currentCardTypes
	SELECT
	MAX([CT].[DimRowId])
	,[CT].[Id] AS [CardTypeId]
	,[CT].[Name]
	FROM [dbo].[dim_CardTypes] [CT] WITH (NOLOCK)
	LEFT JOIN [dbo].[udtf_CurrentBoards_0_2](@boardId) [CB] ON [CB].[BoardId] = [CT].[BoardId]
	WHERE
	[CT].[ContainmentEndDate] IS NULL
	AND [CT].[IsApproximate] = 0
	AND ([CT].[IsDeleted] = 0 OR [CT].[IsDeleted] IS NULL)
	AND [CT].[BoardId] = @boardId
	GROUP BY [CT].[Id], [CT].[Name]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentCardTypesInOrg_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the current list of card types for a given Organization Id
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentCardTypesInOrg_0_2] 
(	
	@organizationId BIGINT
)
RETURNS @currentCardTypes TABLE 
(
	[DimRowId] BIGINT,
	[CardTypeId] BIGINT,
	[Name] NVARCHAR(64)
)
AS
BEGIN

	INSERT INTO @currentCardTypes
	SELECT
	MAX([CT].[DimRowId])
	,[CT].[Id] AS [CardTypeId]
	,[CT].[Name]
	FROM [dbo].[dim_CardTypes] [CT] WITH (NOLOCK)
	LEFT JOIN [dbo].[udtf_CurrentBoardsInOrg_0_2](@organizationId) [CB] ON [CB].[BoardId] = [CT].[BoardId]
	WHERE
	[CT].[ContainmentEndDate] IS NULL
	AND [CT].[IsApproximate] = 0
	AND ([CT].[IsDeleted] = 0 OR [CT].[IsDeleted] IS NULL)
	GROUP BY [CT].[Id], [CT].[Name]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentClassesOfService]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[udtf_CurrentClassesOfService] 
(	
	@boardId	BIGINT
)
RETURNS @currentClassesOfService TABLE 
(
	DimRowId			BIGINT,
	ClassOfServiceId	BIGINT,
	Title				NVARCHAR(255)
)
AS
BEGIN

	INSERT INTO @currentClassesOfService
	SELECT
		MAX(cs.[DimRowId]), cs.[Id] AS [ClassOfServiceId], cs.[Title]
	FROM [dbo].[dim_ClassOfService] cs WITH (NOLOCK)
	WHERE cs.[ContainmentEndDate] IS NULL
	AND cs.[IsApproximate] = 0
	AND cs.[IsDeleted] = 0
	AND cs.[BoardId] = @boardId
	GROUP BY cs.[Id], cs.[Title]

	RETURN
END








GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentClassesOfService_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the current list of class of service for a given Board Id
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentClassesOfService_0_2] 
(	
	@boardId BIGINT
)
RETURNS @currentClassesOfService TABLE 
(
	[DimRowId] BIGINT,
	[ClassOfServiceId] BIGINT,
	[Title] NVARCHAR(255)
)
AS
BEGIN

	INSERT INTO @currentClassesOfService
	SELECT
	MAX([CS].[DimRowId])
	,[CS].[Id] AS [ClassOfServiceId]
	,[CS].[Title]
	FROM [dbo].[dim_ClassOfService] [CS] WITH (NOLOCK)
	LEFT JOIN [dbo].[udtf_CurrentBoards_0_2](@boardId) [CB] ON [CB].[BoardId] = [CS].[BoardId]
	WHERE
	[CS].[ContainmentEndDate] IS NULL
	AND [CS].[IsApproximate] = 0
	AND [CS].[IsDeleted] = 0
	AND [CS].[BoardId] = @boardId
	GROUP BY [CS].[Id], [CS].[Title]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentClassesOfServiceInOrg_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the current list of class of service for a given Organization Id
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentClassesOfServiceInOrg_0_2] 
(	
	@organizationId BIGINT
)
RETURNS @currentClassesOfService TABLE 
(
	[DimRowId] BIGINT,
	[ClassOfServiceId] BIGINT,
	[Title] NVARCHAR(255)
)
AS
BEGIN

	INSERT INTO @currentClassesOfService
	SELECT
	MAX([CS].[DimRowId])
	,[CS].[Id] AS [ClassOfServiceId]
	,[CS].[Title]
	FROM [dbo].[dim_ClassOfService] [CS] WITH (NOLOCK)
	LEFT JOIN [dbo].[udtf_CurrentBoardsInOrg_0_2](@organizationId) [CB] ON [CB].[BoardId] = [CS].[BoardId]
	WHERE
	[CS].[ContainmentEndDate] IS NULL
	AND [CS].[IsApproximate] = 0
	AND [CS].[IsDeleted] = 0
	GROUP BY [CS].[Id], [CS].[Title]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentLanes]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO







-- =============================================
-- Author:		Chris Gundersen
-- Create date: 06-Apr-2015
-- Description:	Designed to get the current list of lanes for a board ID
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentLanes] 
(	
	@boardId	BIGINT
)
RETURNS @currentLanes TABLE 
(
	DimRowId	BIGINT,
	BoardId		BIGINT,
	LaneId		BIGINT,
	Title		NVARCHAR(255),
	LaneTypeId	BIGINT,
	[Type]		INT,
	ParentLaneId	BIGINT,
	[Index]			INT,
	IsDrillthroughDoneLane	BIT
)
AS
BEGIN

	INSERT INTO @currentLanes
	SELECT
		MAX(l.[DimRowId]), l.[BoardId] AS [BoardId], l.[Id] AS [LaneId], l.[Title], l.[LaneTypeId], l.[Type], l.[ParentLaneId], l.[Index], l.[IsDrillthroughDoneLane]
	FROM [dbo].[dim_Lane] l WITH (NOLOCK)
	WHERE l.[BoardId] = @boardId
	AND l.[ContainmentEndDate] IS NULL
	AND l.[IsApproximate] = 0
	AND l.[IsDeleted] = 0
	AND l.[TaskBoardId] IS NULL
	GROUP BY l.[BoardId], l.[Id], l.[Title], l.[LaneTypeId], l.[Type], l.[ParentLaneId], l.[Index], l.[IsDrillthroughDoneLane]

	RETURN
END









GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentLanes_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[udtf_CurrentLanes_0_2] 
(	
	@boardId BIGINT
)
RETURNS @currentLanes TABLE 
(
	[DimRowId] BIGINT,
	[BoardId] BIGINT,
	[BoardTitle] NVARCHAR(4000),
	[LaneId] BIGINT,
	[Title] NVARCHAR(255),
	[LaneTypeId] BIGINT,
	[Type] INT,
	[ParentLaneId] BIGINT,
	[Index] INT,
	[IsDrillthroughDoneLane] BIT,
	[FullLaneTitle] NVARCHAR(4000),
	[OrganizationId] BIGINT
)
AS
BEGIN

	INSERT INTO @currentLanes
	SELECT
	MAX([L].[DimRowId])
	,[L].[BoardId] AS [BoardId]
	,[CB].[Title] AS [BoardTitle]
	,[L].[Id] AS [LaneId]
	,[L].[Title]
	,[L].[LaneTypeId]
	,[L].[Type]
	,[L].[ParentLaneId]
	,[L].[Index]
	,[L].[IsDrillthroughDoneLane]
	,CASE WHEN [L].[ParentLaneId] IS NOT NULL THEN [PL].Title + ' -> ' + [L].Title ELSE [L].Title END AS FullLaneTitle
	,[CB].[OrganizationId]
	FROM [dbo].[dim_Lane] [L] WITH (NOLOCK)
	LEFT JOIN [dbo].[dim_Lane] [PL] ON L.ParentLaneId = PL.Id
	JOIN [dbo].[udtf_CurrentBoards_0_2](@boardId) [CB] ON [CB].[BoardId] = [L].[BoardId]
	WHERE
	[L].[ContainmentEndDate] IS NULL
	AND [L].[IsApproximate] = 0
	AND [L].[IsDeleted] = 0
	AND [L].[TaskBoardId] IS NULL
	AND [PL].[ContainmentEndDate] IS NULL
	AND ([PL].[IsDeleted] = 0 OR [PL].[IsDeleted] IS NULL)
	AND [PL].[TaskBoardId] IS NULL
	AND ([PL].[IsApproximate] = 0 OR [PL].[IsApproximate] IS NULL)
	AND [L].[BoardId] = @boardId
	GROUP BY [L].[BoardId], [L].[Id], [L].[Title], [L].[LaneTypeId], [L].[Type], [L].[ParentLaneId], [L].[Index], [L].[IsDrillthroughDoneLane], [CB].[Title], [PL].Title, [CB].[OrganizationId]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentLanesInOrg_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the current list of lanes for a given Organization Id
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentLanesInOrg_0_2]
(	
	@organizationId	BIGINT
)
RETURNS @currentLanes TABLE 
(
	[DimRowId] BIGINT,
	[BoardId] BIGINT,
	[BoardTitle] NVARCHAR(255),
	[LaneId] BIGINT,
	[Title] NVARCHAR(255),
	[LaneTypeId] BIGINT,
	[Type] INT,
	[ParentLaneId] BIGINT,
	[Index] INT,
	[IsDrillthroughDoneLane] BIT,
	[FullLaneTitle] NVARCHAR(510),
	[OrganizationId] BIGINT
)
AS
BEGIN

	INSERT INTO @currentLanes
	SELECT
	MAX([L].[DimRowId])
	,[L].[BoardId] AS [BoardId]
	,[CB].[Title] AS [BoardTitle]
	,[L].[Id] AS [LaneId]
	,[L].[Title]
	,[L].[LaneTypeId]
	,[L].[Type]
	,[L].[ParentLaneId]
	,[L].[Index]
	,[L].[IsDrillthroughDoneLane]
	,CASE WHEN [L].[ParentLaneId] IS NOT NULL THEN [PL].Title + ' -> ' + [L].Title ELSE [L].Title END AS FullLaneTitle
	,[CB].[OrganizationId]
	FROM [dbo].[dim_Lane] [L] WITH (NOLOCK)
	LEFT JOIN [dbo].[dim_Lane] [PL] ON L.ParentLaneId = PL.Id
	JOIN [dbo].[udtf_CurrentBoardsInOrg_0_2](@organizationId) [CB] ON [CB].[BoardId] = [L].[BoardId]
	WHERE
	[L].[ContainmentEndDate] IS NULL
	AND [L].[IsApproximate] = 0
	AND [L].[IsDeleted] = 0
	AND [L].[TaskBoardId] IS NULL
	AND [PL].[ContainmentEndDate] IS NULL
	AND ([PL].[IsDeleted] = 0 OR [PL].[IsDeleted] IS NULL)
	AND [PL].[TaskBoardId] IS NULL
	AND ([PL].[IsApproximate] = 0 OR [PL].[IsApproximate] IS NULL)
	GROUP BY [L].[BoardId], [L].[Id], [L].[Title], [L].[LaneTypeId], [L].[Type], [L].[ParentLaneId], [L].[Index], [L].[IsDrillthroughDoneLane], [CB].[Title], [PL].Title, [CB].[OrganizationId]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentTaskboardLanes_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the current list of taskboard lanes for a given Board Id
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentTaskboardLanes_0_2] 
(	
	@boardId BIGINT
)
RETURNS @currentLanes TABLE 
(
	[DimRowId] BIGINT,
	[BoardId] BIGINT,
	[BoardTitle] NVARCHAR(255),
	[LaneId] BIGINT,
	[Title] NVARCHAR(255),
	[LaneTypeId] BIGINT,
	[Type] INT,
	[Index] INT,
	[OrganizationId] BIGINT
)
AS
BEGIN

	INSERT INTO @currentLanes
	SELECT
	MAX([L].[DimRowId])
	,[L].[BoardId] AS [BoardId]
	,[CB].[Title] AS [BoardTitle]
	,[L].[Id] AS [LaneId]
	,[L].[Title]
	,[L].[LaneTypeId]
	,[L].[Type]
	,[L].[Index]
	,[CB].[OrganizationId]
	FROM [dbo].[dim_Lane] [L] WITH (NOLOCK)
	JOIN [dbo].[udtf_CurrentBoards_0_2](@boardId) [CB] ON [CB].[BoardId] = [L].[BoardId]
	WHERE
	[L].[ContainmentEndDate] IS NULL
	AND [L].[IsApproximate] = 0
	AND [L].[IsDeleted] = 0
	AND [L].[TaskBoardId] IS NOT NULL
	AND [L].[BoardId] = @boardId
	GROUP BY [L].[BoardId], [L].[Id], [L].[Title], [L].[LaneTypeId], [L].[Type], [L].[Index], [CB].[Title], [CB].[OrganizationId]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentTaskboardLanesInOrg_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the current list of taskboard lanes for a given Organization Id
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentTaskboardLanesInOrg_0_2] 
(	
	@organizationId	BIGINT
)
RETURNS @currentLanes TABLE 
(
	[DimRowId] BIGINT,
	[BoardId] BIGINT,
	[BoardTitle] NVARCHAR(255),
	[LaneId] BIGINT,
	[Title] NVARCHAR(255),
	[LaneTypeId] BIGINT,
	[Type] INT,
	[Index] INT,
	[OrganizationId] BIGINT
)
AS
BEGIN

	INSERT INTO @currentLanes
	SELECT
	MAX([L].[DimRowId])
	,[L].[BoardId] AS [BoardId]
	,[CB].[Title] AS [BoardTitle]
	,[L].[Id] AS [LaneId]
	,[L].[Title]
	,[L].[LaneTypeId]
	,[L].[Type]
	,[L].[Index]
	,[CB].[OrganizationId]
	FROM [dbo].[dim_Lane] [L] WITH (NOLOCK)
	JOIN [dbo].[udtf_CurrentBoardsInOrg_0_2](@organizationId) [CB] ON [CB].[BoardId] = [L].[BoardId]
	WHERE
	[L].[ContainmentEndDate] IS NULL
	AND [L].[IsApproximate] = 0
	AND [L].[IsDeleted] = 0
	AND [L].[TaskBoardId] IS NOT NULL
	GROUP BY [L].[BoardId], [L].[Id], [L].[Title], [L].[LaneTypeId], [L].[Type], [L].[Index], [CB].[Title], [CB].[OrganizationId]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentTaskCards_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the current list of task cards for a given Board Id
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentTaskCards_0_2] 
(	
	@boardId BIGINT
)
RETURNS @currentTaskCards TABLE 
(
	[DimRowId] BIGINT,
	[BoardId] BIGINT,
	[LaneId] BIGINT,
	[CardId] BIGINT,
	[Size] INT,
	[TypeId] BIGINT,
	[ClassOfServiceId] BIGINT,
	[Priority] INT,
	[Title] NVARCHAR(255)
)
AS
BEGIN

	INSERT INTO @currentTaskCards
	SELECT
	MAX([C].[DimRowId])
	,[CL].[BoardId]
	,[CL].[LaneId]
	,[C].[Id] AS [CardId]
	,[C].[Size]
	,[C].[TypeId]
	,[C].[ClassOfServiceId]
	,[C].[Priority]
	,[C].[Title]
	FROM [dbo].[dim_Card] [C] WITH (NOLOCK)
	INNER JOIN [dbo].[udtf_CurrentTaskboardLanes_0_2](@boardId) [CL]
		ON [C].[LaneId] = [CL].[LaneId]
	WHERE [C].[ContainmentEndDate] IS NULL
	AND [C].[IsApproximate] = 0
	AND [C].[IsDeleted] = 0
	AND [CL].[BoardId] = @boardId
	GROUP BY [CL].[BoardId], [CL].[LaneId], [C].[Id], [C].[Size], [C].[TypeId], [C].[ClassOfServiceId], [C].[Priority], [C].[Title]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentTaskCardsInOrg_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
-- =============================================
-- Author:		Austin Young
-- Create date: 11-May-2015
-- Description:	Designed to get the current list of task cards for a given Organization Id
-- =============================================
CREATE FUNCTION [dbo].[udtf_CurrentTaskCardsInOrg_0_2] 
(	
	@organizationId BIGINT
)
RETURNS @currentTaskCards TABLE 
(
	[DimRowId] BIGINT,
	[BoardId] BIGINT,
	[LaneId] BIGINT,
	[CardId] BIGINT,
	[Size] INT,
	[TypeId] BIGINT,
	[ClassOfServiceId] BIGINT,
	[Priority] INT,
	[Title] NVARCHAR(255)
)
AS
BEGIN

	INSERT INTO @currentTaskCards
	SELECT
	MAX([C].[DimRowId])
	,[CL].[BoardId]
	,[CL].[LaneId]
	,[C].[Id] AS [CardId]
	,[C].[Size]
	,[C].[TypeId]
	,[C].[ClassOfServiceId]
	,[C].[Priority]
	,[C].[Title]
	FROM [dbo].[dim_Card] [C] WITH (NOLOCK)
	INNER JOIN [dbo].[udtf_CurrentTaskboardLanesInOrg_0_2](@organizationId) [CL]
		ON [C].[LaneId] = [CL].[LaneId]
	WHERE [C].[ContainmentEndDate] IS NULL
	AND [C].[IsApproximate] = 0
	AND [C].[IsDeleted] = 0
	GROUP BY [CL].[BoardId], [CL].[LaneId], [C].[Id], [C].[Size], [C].[TypeId], [C].[ClassOfServiceId], [C].[Priority], [C].[Title]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentUser]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[udtf_CurrentUser] 
(	
	@userId	BIGINT
)
RETURNS @currentUser TABLE 
(
	DimRowId	BIGINT,
	UserId		BIGINT,
	EmailAddress	NVARCHAR(255),
	IsAccountOwner	BIT,
	IsOrgAdmin	BIT,
	IsEnabled	BIT
)
AS
BEGIN

	INSERT INTO @currentUser
	SELECT
		MAX(u.[DimRowId]), u.[Id] AS [UserId], u.[EmailAddress], u.[IsAccountOwner], u.[Administrator] AS [IsOrgAdmin], u.[Enabled] AS [IsEnabled]
	FROM [dbo].[dim_User] u WITH (NOLOCK)
	WHERE u.[Id] = @userId
	AND u.[ContainmentEndDate] IS NULL
	AND u.[IsApproximate] = 0
	AND u.[IsDeleted] = 0
	GROUP BY u.[Id], u.[EmailAddress], u.[IsAccountOwner], u.[Administrator], u.[Enabled]

	RETURN
END


GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentUser_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[udtf_CurrentUser_0_2] 
(	
	@userId	BIGINT
)
RETURNS @currentUser TABLE 
(
	[DimRowId] BIGINT,
	[UserId] BIGINT,
	[EmailAddress] NVARCHAR(255),
	[IsAccountOwner] BIT,
	[IsOrgAdmin] BIT,
	[IsEnabled] BIT
)
AS
BEGIN

	INSERT INTO @currentUser
	SELECT
	MAX([U].[DimRowId])
	,[U].[Id] AS [UserId]
	,[U].[EmailAddress]
	,[U].[IsAccountOwner]
	,[U].[Administrator] AS [IsOrgAdmin]
	,[U].[Enabled] AS [IsEnabled]
	FROM [dbo].[dim_User] [U] WITH (NOLOCK)
	WHERE [U].[Id] = @userId
	AND [U].[ContainmentEndDate] IS NULL
	AND [U].[IsApproximate] = 0
	AND [U].[IsDeleted] = 0
	GROUP BY [U].[Id], [U].[EmailAddress], [U].[IsAccountOwner], [U].[Administrator], [U].[Enabled]

	RETURN
END

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentUsersInOrg]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[udtf_CurrentUsersInOrg] 
(	
	@orgId	BIGINT
)
RETURNS @currentUsers TABLE 
(
	DimRowId	BIGINT,
	UserId		BIGINT,
	EmailAddress	NVARCHAR(255),
	IsAccountOwner	BIT,
	IsOrgAdmin	BIT,
	IsEnabled	BIT
)
AS
BEGIN

	INSERT INTO @currentUsers
	SELECT
		MAX(u.[DimRowId]), u.[Id] AS [UserId], u.[EmailAddress], u.[IsAccountOwner], u.[Administrator] AS [IsOrgAdmin], u.[Enabled] AS [IsEnabled]
	FROM [dbo].[dim_User] u WITH (NOLOCK)
	WHERE u.[OrganizationId] = @orgId
	AND u.[ContainmentEndDate] IS NULL
	AND u.[IsApproximate] = 0
	AND u.[IsDeleted] = 0
	GROUP BY u.[Id], u.[EmailAddress], u.[IsAccountOwner], u.[Administrator], u.[Enabled]

	RETURN
END



GO
/****** Object:  UserDefinedFunction [dbo].[udtf_CurrentUsersInOrg_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[udtf_CurrentUsersInOrg_0_2] 
(	
	@organizationId	BIGINT
)
RETURNS @currentUsers TABLE 
(
	[DimRowId] BIGINT,
	[UserId] BIGINT,
	[EmailAddress] NVARCHAR(255),
	[IsAccountOwner] BIT,
	[IsOrgAdmin] BIT,
	[IsEnabled] BIT,
	[FullName] NVARCHAR(255)
)
AS
BEGIN

	INSERT INTO @currentUsers
	SELECT
	MAX([U].[DimRowId])
	,[U].[Id] AS [UserId]
	,[U].[EmailAddress]
	,[U].[IsAccountOwner]
	,[U].[Administrator] AS [IsOrgAdmin]
	,[U].[Enabled] AS [IsEnabled]
	,[U].[LastName] + ', ' + [U].[FirstName] AS [FullName]
	FROM [dbo].[dim_User] [U] WITH (NOLOCK)
	WHERE
	[U].[OrganizationId] = @organizationId
	AND [U].[ContainmentEndDate] IS NULL
	AND [U].[IsApproximate] = 0
	AND [U].[IsDeleted] = 0
	GROUP BY [U].[Id], [U].[EmailAddress], [U].[IsAccountOwner], [U].[Administrator], [U].[Enabled], [U].[FirstName], [U].[LastName]

	RETURN
END

GO
/****** Object:  Table [dbo].[__metadata]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[__metadata](
	[metakey] [nvarchar](50) NOT NULL,
	[metavalue] [nvarchar](255) NOT NULL,
	[notes] [nvarchar](500) NULL,
 CONSTRAINT [PK___metadata] PRIMARY KEY CLUSTERED 
(
	[metakey] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[__MigrationLog]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[__MigrationLog](
	[migration_id] [uniqueidentifier] NOT NULL,
	[script_checksum] [nvarchar](64) NOT NULL,
	[script_filename] [nvarchar](255) NOT NULL,
	[complete_dt] [datetime2](7) NOT NULL,
	[applied_by] [nvarchar](100) NOT NULL,
	[deployed] [tinyint] NOT NULL,
	[version] [varchar](255) NULL,
	[package_version] [varchar](255) NULL,
	[release_version] [varchar](255) NULL,
	[sequence_no] [int] IDENTITY(1,1) NOT NULL,
 CONSTRAINT [PK___MigrationLog] PRIMARY KEY CLUSTERED 
(
	[migration_id] ASC,
	[complete_dt] ASC,
	[script_checksum] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[_BoardCardCache]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[_BoardCardCache](
	[BoardCardCacheId] [bigint] IDENTITY(1,1) NOT NULL,
	[BoardId] [bigint] NOT NULL,
	[CardId] [bigint] NOT NULL,
	[DimRowId] [bigint] NOT NULL,
 CONSTRAINT [PK__BoardCardCache] PRIMARY KEY CLUSTERED 
(
	[BoardCardCacheId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[_BoardCardTag]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[_BoardCardTag](
	[BoardCardTagId] [bigint] IDENTITY(1,1) NOT NULL,
	[BoardTagId] [bigint] NOT NULL,
	[CardId] [bigint] NOT NULL,
 CONSTRAINT [PK__BoardCardTag] PRIMARY KEY CLUSTERED 
(
	[BoardCardTagId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[_BoardTag]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[_BoardTag](
	[BoardTagId] [bigint] IDENTITY(1,1) NOT NULL,
	[BoardId] [bigint] NOT NULL,
	[Tag] [nvarchar](2000) NOT NULL,
	[cs_Tag]  AS (checksum([Tag])),
 CONSTRAINT [PK__BoardTags] PRIMARY KEY CLUSTERED 
(
	[BoardTagId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[_CardTagCache]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[_CardTagCache](
	[CardTagCacheId] [bigint] IDENTITY(1,1) NOT NULL,
	[BoardId] [bigint] NOT NULL,
	[CardId] [bigint] NOT NULL,
	[TagChecksum] [int] NULL,
 CONSTRAINT [PK__CardTagCache] PRIMARY KEY CLUSTERED 
(
	[CardTagCacheId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[_EntityException]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[_EntityException](
	[Id] [bigint] IDENTITY(1,1) NOT NULL,
	[EntityId] [bigint] NOT NULL,
	[EntityType] [int] NOT NULL,
	[ReferenceEntityId] [bigint] NULL,
	[ReferenceEntityType] [int] NULL,
	[ExceptionType] [int] NULL,
 CONSTRAINT [PK__EntityException] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[_Numbers]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[_Numbers](
	[Number] [bigint] NOT NULL,
 CONSTRAINT [PK__Numbers] PRIMARY KEY CLUSTERED 
(
	[Number] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_Account]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_Account](
	[DimRowId] [bigint] IDENTITY(1,1) NOT NULL,
	[Id] [bigint] NOT NULL,
	[UserLimit] [int] NULL,
	[BoardLimit] [int] NULL,
	[BoardViewerLimit] [int] NULL,
	[BillingId] [bigint] NULL,
	[AccountTypeId] [int] NOT NULL,
	[AccountStatusId] [int] NOT NULL,
	[PaymentPeriodId] [int] NOT NULL,
	[VaultId] [nvarchar](255) NULL,
	[BillingDay] [int] NULL,
	[AccountValidUntilDate] [datetime] NULL,
	[AllowMultiUserAssignments] [bit] NULL,
	[IsSslEnabled] [bit] NULL,
	[OrganizationDashboardEnabled] [bit] NULL,
	[ClassOfServiceEnabled] [bit] NULL,
	[ExternalCardIdEnabled] [bit] NULL,
	[CreationDate] [datetime] NULL,
	[AllowBoardCloning] [bit] NULL,
	[AllowBoardTemplatesCreate] [bit] NULL,
	[AllowBoardTemplatesImportExport] [bit] NULL,
	[AllowAllTemplates] [bit] NULL,
	[AllowRepliableNotifications] [bit] NULL,
	[DiscountCode] [nvarchar](255) NULL,
	[EnableTaskBoards] [bit] NULL,
	[EnableDrillThroughBoards] [bit] NULL,
	[AllowAttachments] [bit] NULL,
	[MaxFileSize] [int] NULL,
	[MaxStorageAllowed] [bigint] NULL,
	[Country] [nvarchar](255) NULL,
	[Region] [nvarchar](255) NULL,
	[IsTrialExtended] [bit] NULL,
	[AccountOwnerId] [bigint] NULL,
	[MaxImportFileSize] [int] NULL,
	[EnableAdvancedRoleSecurity] [bit] NULL,
	[EnablePrivateBoards] [bit] NULL,
	[NumberOfPrivateBoards] [int] NULL,
	[DefaultRoleId] [int] NULL,
	[UsersToShow] [int] NULL,
	[EnableUserAdminReports] [bit] NULL,
	[EnableImportExportCards] [bit] NULL,
	[EnableExportBoardHistory] [bit] NULL,
	[EnableBoardViewers] [bit] NULL,
	[EnableCumulativeFlowDiagram] [bit] NULL,
	[EnableCycleTimeDiagram] [bit] NULL,
	[EnableCardDistributionDiagram] [bit] NULL,
	[EnableEfficiencyDiagram] [bit] NULL,
	[EnableProcessControlDiagram] [bit] NULL,
	[NumberOfTaskboardsCategories] [int] NULL,
	[AllowFocusedObjectiveSimulation] [int] NULL,
	[EnableInvitationSystem] [bit] NULL,
	[MaxNumberOfInvitations] [int] NULL,
	[AllowInvitationsFromAllUsers] [bit] NULL,
	[DisallowedFileExtensions] [nvarchar](255) NULL,
	[EnableSignalRForBoardUpdates] [bit] NULL,
	[AllowCardsInBoardTemplates] [bit] NULL,
	[EnableAdvancedSecurity] [bit] NULL,
	[DisableRssFeeds] [bit] NULL,
	[AllowMoveCardsBetweenBoards] [bit] NULL,
	[HubSpotVisitorId] [nvarchar](64) NULL,
	[DisableGenericLogin] [bit] NULL,
	[RegistrationIp] [nvarchar](255) NULL,
	[DisableRememberMe] [bit] NULL,
	[DisableDisallowedFileExtensions] [bit] NULL,
	[EnableElasticSearch] [bit] NOT NULL,
	[EnableSearchByInternalCardId] [bit] NOT NULL,
	[EnableGlobalSearch] [bit] NOT NULL,
	[AllowHorizontalCollapse] [bit] NULL,
	[EnableRefreshAnalyticsData] [bit] NULL,
	[EnableUserMentions] [bit] NULL,
	[NumberOfDaysToRetrieveAnalyticsEventsFor] [int] NOT NULL,
	[PropertyToUseForAnalyticsCutoff] [varchar](100) NOT NULL,
	[ArchiveCardDays] [int] NULL,
	[AllowTaskboardCategoryEdit] [bit] NOT NULL,
	[AllowTaskTypeFiltering] [bit] NOT NULL,
	[AllowSeparateCardAndTaskTypes] [bit] NOT NULL,
	[EnableBoardCreatorRole] [bit] NULL,
	[EnableTagManagement] [bit] NULL,
	[EnableSharedBoards] [bit] NULL,
	[EnableCustomBoardUrls] [bit] NULL,
	[DisableCalendarView] [bit] NULL,
	[allowBoardCreationFromTemplates] [bit] NULL,
	[allowHorizontalSplitInBoardEdit] [bit] NULL,
	[allowAddCardTypes] [bit] NULL,
	[enableFilters] [bit] NULL,
	[enableActivityStream] [bit] NULL,
	[enableSearch] [bit] NULL,
	[EnableImportCards] [bit] NULL,
	[EnableExportCards] [bit] NULL,
	[AllowApiUserManagement] [bit] NOT NULL,
	[DefaultNumberOfDaysForApiKeyExpiration] [int] NOT NULL,
	[EnableCardDelegation] [bit] NULL,
	[EnableSuspensionWarning] [bit] NULL,
	[SubscribeUsersToAssignedCardsByDefault] [bit] NULL,
	[FreshbooksClientId] [nvarchar](100) NULL,
	[SalesPersonId] [int] NULL,
	[EnableSingleSignOn] [bit] NULL,
	[IdProviderUrl] [nvarchar](255) NULL,
	[IdProviderKey] [nvarchar](max) NULL,
	[EnableDrillThroughDoneLane] [bit] NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[StartUserId] [bigint] NULL,
	[EndUserId] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[EntityExceptionId] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
	[DefaultNewBoardRole] [int] NULL,
	[EnableUserDevice] [bit] NULL,
	[AllowColorForClassOfServices] [bit] NULL,
	[AllowComments] [bit] NULL,
	[EnableOrganizationSettings] [bit] NULL,
	[EnableLanePolicies] [bit] NULL,
	[EnableLaneSubscription] [bit] NULL,
	[EnableCardHistory] [bit] NULL,
	[EnableWipLimit] [bit] NULL,
	[ChurnDate] [datetime] NULL,
	[AdminsContact] [nvarchar](255) NULL,
	[PoliciesUrl] [nvarchar](255) NULL,
	[AllowTableauCharts] [bit] NULL,
	[EnableConstraintLogReport] [bit] NULL,
	[EnablePlannedPercentCompleteReport] [bit] NULL,
	[EnableSelectAllUsers] [bit] NULL,
	[EnableNewCardConnectionsUI] [bit] NULL,
	[EnableNewBoardUserAdminUI] [bit] NULL,
	[EnableMultipleDrillThroughBoards] [bit] NULL,
	[EnableSameBoardConnections] [bit] NULL,
	[AllowedSharedBoardRoles] [int] NULL,
	[OmitSharedBoardReaders] [bit] NULL,
	[EnableBurndownDiagram] [bit] NULL,
	[EnableRealTimeCommunication] [bit] NULL,
	[EnableQuickConnectionsUI] [bit] NULL,
	[EnableReportingApi] [bit] NULL,
	[ReportingApiTokenExpirationInMinutes] [int] NULL,
	[ReportingApiResponseCacheDurationInMinutes] [int] NULL,
	[LoginPageBannerText] [nvarchar](1000) NULL,
	[EnableReportingApiCardExport] [bit] NULL,
	[EnableReportingApiCardLaneHistory] [bit] NULL,
	[EnableReportingApiCurrentUserAssignments] [bit] NULL,
	[EnableReportingApiHistoricalUserAssignments] [bit] NULL,
 CONSTRAINT [PK__dim_Acco__FB223AD2D8B64B4F] PRIMARY KEY CLUSTERED 
(
	[DimRowId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_Board]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_Board](
	[DimRowId] [bigint] IDENTITY(1,1) NOT NULL,
	[Id] [bigint] NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[Title] [nvarchar](255) NULL,
	[Description] [nvarchar](1000) NULL,
	[CreationDate] [datetime] NULL,
	[Active] [bit] NULL,
	[IsArchived] [bit] NULL,
	[CardColorField] [int] NOT NULL,
	[ClassOfServiceEnabled] [bit] NULL,
	[IsCardIdEnabled] [bit] NULL,
	[IsHeaderEnabled] [bit] NULL,
	[IsHyperlinkEnabled] [bit] NULL,
	[IsPrefixEnabled] [bit] NULL,
	[IsPrefixIncludedInHyperlink] [bit] NULL,
	[Prefix] [nvarchar](255) NULL,
	[Format] [nvarchar](255) NULL,
	[BaseWipOnCardSize] [bit] NULL,
	[ExcludeCompletedAndArchiveViolations] [bit] NULL,
	[ExcludeFromOrgAnalytics] [bit] NULL,
	[Version] [bigint] NULL,
	[OrganizationId] [bigint] NOT NULL,
	[CardDefinitionId] [bigint] NULL,
	[IsDuplicateCardIdAllowed] [bit] NULL,
	[IsAutoIncrementCardIdEnabled] [bit] NULL,
	[CurrentExternalCardId] [bigint] NULL,
	[IsPrivate] [bit] NULL,
	[IsWelcome] [bit] NULL,
	[ThumbnailVersion] [bigint] NULL,
	[BoardCreatorId] [bigint] NULL,
	[IsShared] [bit] NULL,
	[SharedBoardRole] [bigint] NULL,
	[CustomBoardMoniker] [varchar](50) NULL,
	[IsPermalinkEnabled] [bit] NULL,
	[IsExternalUrlEnabled] [bit] NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[StartUserId] [bigint] NULL,
	[EndUserId] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[EntityExceptionId] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
	[AllowUsersToDeleteCards] [bit] NULL,
	[CustomIconFieldLabel] [nvarchar](20) NULL,
 CONSTRAINT [PK__dim_Boar__FB223AD2DDCCC3E4] PRIMARY KEY CLUSTERED 
(
	[DimRowId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_BoardRole]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_BoardRole](
	[DimRowId] [bigint] IDENTITY(1,1) NOT NULL,
	[Id] [bigint] NOT NULL,
	[RoleTypeId] [int] NOT NULL,
	[WIP] [int] NULL,
	[BoardId] [bigint] NULL,
	[UserId] [bigint] NULL,
	[IsDeleted] [bit] NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[StartUserId] [bigint] NULL,
	[EndUserId] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[EntityExceptionId] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
 CONSTRAINT [PK__dim_BoardRole__FB223AD255D9E050] PRIMARY KEY CLUSTERED 
(
	[DimRowId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_Card]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_Card](
	[DimRowId] [bigint] IDENTITY(1,1) NOT NULL,
	[Id] [bigint] NOT NULL,
	[Version] [int] NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[Title] [nvarchar](255) NULL,
	[Description] [nvarchar](max) NULL,
	[Active] [bit] NULL,
	[Size] [int] NULL,
	[IsBlocked] [bit] NULL,
	[BlockReason] [nvarchar](255) NULL,
	[CreatedOn] [datetime] NULL,
	[DueDate] [datetime] NULL,
	[Priority] [int] NULL,
	[Index] [int] NULL,
	[ExternalSystemName] [nvarchar](255) NULL,
	[ExternalSystemUrl] [nvarchar](2000) NULL,
	[ExternalCardID] [nvarchar](50) NULL,
	[Tags] [nvarchar](2000) NULL,
	[LaneId] [bigint] NULL,
	[ClassOfServiceId] [bigint] NULL,
	[TypeId] [bigint] NOT NULL,
	[CurrentTaskBoardId] [bigint] NULL,
	[DrillThroughBoardId] [bigint] NULL,
	[ParentCardId] [bigint] NULL,
	[BlockStateChangeDate] [datetime] NULL,
	[LastMove] [datetime] NULL,
	[AttachmentsCount] [int] NULL,
	[LastAttachment] [datetime] NULL,
	[CommentsCount] [int] NULL,
	[LastComment] [datetime] NULL,
	[LastActivity] [datetime] NULL,
	[DateArchived] [datetime] NULL,
	[StartDate] [datetime] NULL,
	[ActualStartDate] [datetime] NULL,
	[ActualFinishDate] [datetime] NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[StartUserId] [bigint] NULL,
	[EndUserId] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[EntityExceptionId] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
	[cs_Tags]  AS (checksum([Tags])),
	[DrillThroughProgressPercentage] [int] NULL,
	[DrillThroughProgressComplete] [int] NULL,
	[DrillThroughProgressTotal] [int] NULL,
	[DrillThroughProgressSizeTotal] [bigint] NULL,
	[DrillThroughProgressSizeComplete] [bigint] NULL,
	[ComputedExternalCardIDTitle] [nvarchar](306) NULL,
 CONSTRAINT [PK__dim_Card__FB223AD26AAF5610] PRIMARY KEY CLUSTERED 
(
	[DimRowId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_CardTypes]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_CardTypes](
	[DimRowId] [bigint] IDENTITY(1,1) NOT NULL,
	[Id] [bigint] NOT NULL,
	[Name] [nvarchar](64) NOT NULL,
	[BoardId] [bigint] NULL,
	[IsCardType] [bit] NOT NULL,
	[IsTaskType] [bit] NOT NULL,
	[IsDefaultTaskType] [bit] NOT NULL,
	[StartUserId] [bigint] NULL,
	[EndUserID] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
	[EntityExceptionId] [bigint] NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[IsDeleted] [bit] NULL,
	[ColorHex] [nvarchar](255) NULL,
	[IsDefault] [bit] NULL,
	[IconPath] [nvarchar](255) NULL,
	[IconName] [nvarchar](255) NULL,
	[IconColor] [nvarchar](50) NULL,
 CONSTRAINT [PK__dim_Card__FB223AD24203F384] PRIMARY KEY CLUSTERED 
(
	[DimRowId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_ClassOfService]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_ClassOfService](
	[DimRowId] [bigint] IDENTITY(1,1) NOT NULL,
	[Id] [bigint] NOT NULL,
	[Title] [nvarchar](255) NOT NULL,
	[BoardId] [bigint] NULL,
	[IsDeleted] [bit] NOT NULL,
	[StartUserId] [bigint] NULL,
	[EndUserID] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
	[EntityExceptionId] [bigint] NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[Policy] [nvarchar](2000) NULL,
	[IconPath] [nvarchar](255) NULL,
	[ColorHex] [nvarchar](7) NULL,
	[CustomIconName] [nvarchar](255) NULL,
	[CustomIconColor] [nvarchar](50) NULL,
 CONSTRAINT [PK__dim_Clas__FB223AD26FFD0E5B] PRIMARY KEY CLUSTERED 
(
	[DimRowId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_CustomCardField]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_CustomCardField](
	[DimRowId] [bigint] IDENTITY(1,1) NOT NULL,
	[Id] [bigint] NULL,
	[OrganizationId] [bigint] NULL,
	[BoardId] [bigint] NULL,
	[Index] [int] NULL,
	[Type] [nvarchar](10) NULL,
	[Label] [nvarchar](50) NOT NULL,
	[HelpText] [nvarchar](255) NULL,
	[IsDeleted] [bit] NULL,
	[CreatedOn] [datetime] NULL,
	[CreatedBy] [bigint] NULL,
	[StartUserId] [bigint] NULL,
	[EndUserID] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
	[EntityExceptionId] [bigint] NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[DimRowId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_CustomCardFieldValue]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_CustomCardFieldValue](
	[DimRowId] [bigint] IDENTITY(1,1) NOT NULL,
	[Id] [bigint] NOT NULL,
	[CustomCardFieldId] [bigint] NOT NULL,
	[CardId] [bigint] NOT NULL,
	[TextValue] [nvarchar](255) NULL,
	[NumberValue] [numeric](18, 4) NULL,
	[StartUserId] [bigint] NULL,
	[EndUserID] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
	[EntityExceptionId] [bigint] NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[DimRowId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_Date]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_Date](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[DateKey] [char](8) NOT NULL,
	[Date] [datetime] NOT NULL,
	[Day] [char](2) NOT NULL,
	[DaySuffix] [varchar](4) NOT NULL,
	[DayOfWeek] [varchar](9) NOT NULL,
	[DOWInMonth] [tinyint] NOT NULL,
	[DayOfYear] [int] NOT NULL,
	[WeekOfYear] [tinyint] NOT NULL,
	[WeekOfMonth] [tinyint] NOT NULL,
	[Month] [char](2) NOT NULL,
	[MonthName] [varchar](9) NOT NULL,
	[Quarter] [tinyint] NOT NULL,
	[QuarterName] [varchar](6) NOT NULL,
	[Year] [char](4) NOT NULL,
	[StandardDate] [varchar](10) NULL,
	[HolidayText] [varchar](50) NULL,
	[DateCompareOrdinal]  AS (CONVERT([bigint],[Id],(0))*(100000)),
 CONSTRAINT [PK_dim_Date] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_Lane]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_Lane](
	[DimRowId] [bigint] IDENTITY(1,1) NOT NULL,
	[Id] [bigint] NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[Title] [nvarchar](255) NULL,
	[Description] [nvarchar](max) NULL,
	[LaneTypeId] [int] NOT NULL,
	[Orientation] [int] NOT NULL,
	[Type] [int] NULL,
	[Active] [bit] NULL,
	[CreationDate] [datetime] NULL,
	[CardLimit] [int] NULL,
	[Width] [smallint] NULL,
	[Index] [int] NULL,
	[BoardId] [bigint] NULL,
	[TaskBoardId] [bigint] NULL,
	[ParentLaneId] [bigint] NULL,
	[ActivityId] [bigint] NULL,
	[CardContextId] [bigint] NULL,
	[IsDrillthroughDoneLane] [bit] NULL,
	[IsDefaultDropLane] [bit] NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[StartUserId] [bigint] NULL,
	[EndUserId] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[EntityExceptionId] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
 CONSTRAINT [PK__dim_Lane__FB223AD255D9E050] PRIMARY KEY CLUSTERED 
(
	[DimRowId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY] TEXTIMAGE_ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_Organization]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_Organization](
	[DimRowId] [bigint] IDENTITY(1,1) NOT NULL,
	[Id] [bigint] NOT NULL,
	[Version] [datetime] NOT NULL,
	[Title] [nvarchar](255) NULL,
	[Description] [nvarchar](1000) NULL,
	[HostName] [nvarchar](255) NULL,
	[RequestedSubscriptionCancelAt] [datetime] NULL,
	[ViewersAllowed] [int] NULL,
	[CreationDate] [datetime] NULL,
	[AccountId] [bigint] NULL,
	[AdvancedSecurity] [nvarchar](1000) NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[StartUserId] [bigint] NULL,
	[EndUserId] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[EntityExceptionId] [bigint] NULL,
 CONSTRAINT [PK__dim_Orga__FB223AD25625F782] PRIMARY KEY CLUSTERED 
(
	[DimRowId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_TaskBoards]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_TaskBoards](
	[DimRowId] [bigint] IDENTITY(1,1) NOT NULL,
	[Id] [bigint] NOT NULL,
	[ProgressPercentage] [int] NULL,
	[CompletedCardCount] [int] NOT NULL,
	[CompletedCardSize] [int] NOT NULL,
	[TotalCards] [int] NULL,
	[TotalSize] [int] NOT NULL,
	[IsDeleted] [bit] NOT NULL,
	[Version] [bigint] NOT NULL,
	[CardContextId] [bigint] NOT NULL,
	[ContainingCardId] [bigint] NULL,
	[BoardId] [bigint] NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[StartUserId] [bigint] NULL,
	[EndUserId] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[EntityExceptionId] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
 CONSTRAINT [PK__dim_Task__FB223AD272FDCC36] PRIMARY KEY CLUSTERED 
(
	[DimRowId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_Time]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_Time](
	[ID] [int] IDENTITY(1,1) NOT NULL,
	[Time] [char](8) NOT NULL,
	[Hour] [char](2) NOT NULL,
	[MilitaryHour] [char](2) NOT NULL,
	[Minute] [char](2) NOT NULL,
	[Second] [char](2) NOT NULL,
	[AmPm] [char](2) NOT NULL,
	[StandardTime] [char](11) NULL,
 CONSTRAINT [PK_dim_Time] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_TimeZone]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_TimeZone](
	[Id] [int] IDENTITY(1,1) NOT NULL,
	[TimeZoneId] [varchar](31) NOT NULL,
	[DisplayName] [varchar](61) NOT NULL,
	[StandardName] [varchar](31) NOT NULL,
	[SupportsDaylightSavingTime] [bit] NOT NULL,
	[UTCOffsetMinutes] [int] NOT NULL,
 CONSTRAINT [PK_dim_TimeZone] PRIMARY KEY CLUSTERED 
(
	[Id] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[dim_User]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[dim_User](
	[DimRowId] [bigint] IDENTITY(1,1) NOT NULL,
	[Id] [bigint] NOT NULL,
	[Username] [nvarchar](255) NULL,
	[EmailAddress] [nvarchar](255) NULL,
	[Administrator] [bit] NULL,
	[Enabled] [bit] NULL,
	[FirstName] [nvarchar](255) NULL,
	[LastName] [nvarchar](255) NULL,
	[TimeZone] [nvarchar](255) NULL,
	[DateFormat] [nvarchar](255) NULL,
	[IsAccountOwner] [bit] NULL,
	[IsDeleted] [bit] NOT NULL,
	[IsSystemAdministrator] [bit] NULL,
	[SendMeEmailCommunicationsAbout] [bit] NULL,
	[KeepMeUpdatedOf] [bit] NULL,
	[LeanKitCommunicationsRead] [bit] NULL,
	[IsSupportAccount] [bit] NULL,
	[OrganizationId] [bigint] NULL,
	[CreationDate] [datetime] NULL,
	[LastLoginAttempt] [datetime] NOT NULL,
	[LoginAttemptCount] [int] NULL,
	[AccountLockTime] [datetime] NOT NULL,
	[LastAccess] [datetime] NULL,
	[BoardCreator] [bit] NULL,
	[ImageVisualization] [int] NOT NULL,
	[ExternalUserName] [nvarchar](255) NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[StartUserId] [bigint] NULL,
	[EndUserId] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[EntityExceptionId] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
	[HasTemporaryPassword] [bit] NULL,
	[Password] [nvarchar](255) NULL,
	[PasswordSalt] [nvarchar](255) NULL,
 CONSTRAINT [PK__dim_User__FB223AD23956A010] PRIMARY KEY CLUSTERED 
(
	[DimRowId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[fact_CardActualStartEndDateContainmentPeriod]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[fact_CardActualStartEndDateContainmentPeriod](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[CardID] [bigint] NOT NULL,
	[ActualStartDate] [datetime] NULL,
	[ActualFinishDate] [datetime] NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[StartUserId] [bigint] NULL,
	[EndUserId] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[EntityExceptionId] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
 CONSTRAINT [PK_fact_CardActualStartEndDateContainmentPeriod] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[fact_CardBlockContainmentPeriod]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[fact_CardBlockContainmentPeriod](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[CardID] [bigint] NOT NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[StartUserId] [bigint] NULL,
	[EndUserId] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[EntityExceptionId] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
 CONSTRAINT [PK_fact_CardBlockContainmentPeriod] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[fact_CardLaneContainmentPeriod]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[fact_CardLaneContainmentPeriod](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[CardID] [bigint] NOT NULL,
	[LaneID] [bigint] NOT NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[StartOrdinal]  AS (CONVERT([bigint],[StartDateKey],(0))*(100000)+[StartTimeKey]),
	[EndOrdinal]  AS (CONVERT([bigint],[EndDateKey],(0))*(100000)+[EndTimeKey]),
	[StartUserId] [bigint] NULL,
	[EndUserId] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[EntityExceptionId] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
 CONSTRAINT [PK_fact_CardLaneContainmentPeriod] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[fact_CardsByOrganization]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[fact_CardsByOrganization](
	[OrganizationId] [bigint] NOT NULL,
	[CardId] [bigint] NOT NULL,
	[IsDeleted] [bit] NOT NULL,
 CONSTRAINT [PK_fact_CardsByOrganization] PRIMARY KEY CLUSTERED 
(
	[OrganizationId] ASC,
	[CardId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[fact_CardStartDueDateContainmentPeriod]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[fact_CardStartDueDateContainmentPeriod](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[CardID] [bigint] NOT NULL,
	[StartDate] [datetime] NULL,
	[DueDate] [datetime] NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[StartUserId] [bigint] NULL,
	[EndUserId] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[EntityExceptionId] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
 CONSTRAINT [PK_fact_CardStartDueDateContainmentPeriod] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[fact_OrgLastCardActivity]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[fact_OrgLastCardActivity](
	[OrganizationId] [bigint] NOT NULL,
	[LastCardActivityDate] [datetime] NOT NULL,
 CONSTRAINT [PK_fact_OrgLastCardActivity] PRIMARY KEY CLUSTERED 
(
	[OrganizationId] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[fact_ReportExecution]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[fact_ReportExecution](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[ReportName] [varchar](50) NOT NULL,
	[OrgId] [bigint] NOT NULL,
	[UserId] [bigint] NOT NULL,
	[BoardId] [bigint] NOT NULL,
	[ExecutionDate] [datetime] NOT NULL,
 CONSTRAINT [PK_fact_ReportExecution] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  Table [dbo].[fact_UserAssignmentContainmentPeriod]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[fact_UserAssignmentContainmentPeriod](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[CardID] [bigint] NOT NULL,
	[ToUserID] [bigint] NOT NULL,
	[ToUserName] [nvarchar](255) NULL,
	[ToUserEmail] [nvarchar](255) NULL,
	[StartDateKey] [int] NOT NULL,
	[StartTimeKey] [int] NOT NULL,
	[EndDateKey] [int] NULL,
	[EndTimeKey] [int] NULL,
	[DurationSeconds] [bigint] NULL,
	[StartUserId] [bigint] NULL,
	[EndUserId] [bigint] NULL,
	[IsApproximate] [bit] NOT NULL,
	[EntityExceptionId] [bigint] NULL,
	[ContainmentStartDate] [datetime] NOT NULL,
	[ContainmentEndDate] [datetime] NULL,
 CONSTRAINT [PK_fact_UserAssignmentContainmentPeriod] PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (PAD_INDEX = OFF, STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, ALLOW_ROW_LOCKS = ON, ALLOW_PAGE_LOCKS = ON) ON [PRIMARY]
) ON [PRIMARY]

GO
/****** Object:  View [dbo].[vw_dim_Current_User]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [dbo].[vw_dim_Current_User] as

--Selects the current record for each board that is not deleted or archived

SELECT
[DimRowId]
      ,[Id]
      ,[Username]
      ,[EmailAddress]
      ,[Administrator]
      ,[Enabled]
      ,[FirstName]
      ,[LastName]
      ,[TimeZone]
      ,[DateFormat]
      ,[IsAccountOwner]
      ,[IsDeleted]
      ,[IsSystemAdministrator]
      ,[SendMeEmailCommunicationsAbout]
      ,[KeepMeUpdatedOf]
      ,[LeanKitCommunicationsRead]
      ,[IsSupportAccount]
      ,[OrganizationId]
      ,[CreationDate]
      ,[LastLoginAttempt]
      ,[LoginAttemptCount]
      ,[AccountLockTime]
      ,[LastAccess]
      ,[BoardCreator]
      ,[ImageVisualization]
      ,[ExternalUserName]
      ,[StartDateKey]
      ,[StartTimeKey]
      ,[EndDateKey]
      ,[EndTimeKey]
      ,[DurationSeconds]
      ,[StartUserId]
      ,[EndUserId]
      ,[IsApproximate]
      ,[EntityExceptionId]
      ,[ContainmentStartDate]
      ,[ContainmentEndDate]
FROM [dbo].[dim_User] U
WHERE U.ContainmentEndDate IS NULL
AND U.IsApproximate = 0 
AND U.IsDeleted = 0 
AND U.Enabled = 1 


GO
/****** Object:  View [dbo].[vw_dim_Current_Board]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [dbo].[vw_dim_Current_Board] as

--Selects the current record for each board that is not deleted or archived

SELECT 
	B.[DimRowId]
      ,B.[Id]
      ,B.[IsDeleted]
      ,B.[Title]
      ,B.[Description]
      ,B.[CreationDate]
      ,B.[Active]
      ,B.[IsArchived]
      ,B.[CardColorField]
      ,B.[ClassOfServiceEnabled]
      ,B.[IsCardIdEnabled]
      ,B.[IsHeaderEnabled]
      ,B.[IsHyperlinkEnabled]
      ,B.[IsPrefixEnabled]
      ,B.[IsPrefixIncludedInHyperlink]
      ,B.[Prefix]
      ,B.[Format]
      ,B.[BaseWipOnCardSize]
      ,B.[ExcludeCompletedAndArchiveViolations]
      ,B.[ExcludeFromOrgAnalytics]
      ,B.[Version]
      ,B.[OrganizationId]
      ,B.[CardDefinitionId]
      ,B.[IsDuplicateCardIdAllowed]
      ,B.[IsAutoIncrementCardIdEnabled]
      ,B.[CurrentExternalCardId]
      ,B.[IsPrivate]
      ,B.[IsWelcome]
      ,B.[ThumbnailVersion]
      ,B.[BoardCreatorId]
      ,B.[IsShared]
      ,B.[SharedBoardRole]
      ,B.[CustomBoardMoniker]
      ,B.[IsPermalinkEnabled]
      ,B.[IsExternalUrlEnabled]
      ,B.[StartDateKey]
      ,B.[StartTimeKey]
      ,B.[EndDateKey]
      ,B.[EndTimeKey]
      ,B.[DurationSeconds]
      ,B.[StartUserId]
      ,B.[EndUserId]
      ,B.[IsApproximate]
      ,B.[EntityExceptionId]
      ,B.[ContainmentStartDate]
      ,B.[ContainmentEndDate]
	  ,BC.EmailAddress AS BoardCreator
FROM [dbo].[dim_Board] B
LEFT JOIN [dbo].[vw_dim_Current_User] BC ON BC.Id = B.BoardCreatorId
WHERE B.ContainmentEndDate IS NULL
AND B.IsApproximate = 0 
AND B.IsDeleted = 0 
AND B.IsArchived = 0 


GO
/****** Object:  View [dbo].[vw_dim_Current_TaskboardLane]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [dbo].[vw_dim_Current_TaskboardLane] as

--Selects the current record for each lane lane on a board that is not deleted 
--and that does not belong to a board that is deleted or archive

SELECT 
	L.[DimRowId]
      ,L.[Id]
      ,L.[IsDeleted]
      ,L.[Title]
      ,L.[Description]
      ,L.[LaneTypeId]
      ,L.[Orientation]
      ,L.[Type]
      ,L.[Active]
      ,L.[CreationDate]
      ,L.[CardLimit]
      ,L.[Width]
      ,L.[Index]
      ,L.[BoardId]
      ,L.[TaskBoardId]
      ,L.[ParentLaneId]
      ,L.[ActivityId]
      ,L.[CardContextId]
      ,L.[IsDrillthroughDoneLane]
      ,L.[IsDefaultDropLane]
      ,L.[StartDateKey]
      ,L.[StartTimeKey]
      ,L.[EndDateKey]
      ,L.[EndTimeKey]
      ,L.[DurationSeconds]
      ,L.[StartUserId]
      ,L.[EndUserId]
      ,L.[IsApproximate]
      ,L.[EntityExceptionId]
      ,L.[ContainmentStartDate]
      ,L.[ContainmentEndDate]
      ,B.OrganizationId
	  ,B.Title AS BoardTitle
FROM [dbo].[dim_Lane] L
JOIN [dbo].[vw_dim_Current_Board] B ON B.id = L.BoardId
LEFT JOIN [dbo].[dim_Lane] PL ON L.ParentLaneId = PL.Id
WHERE L.ContainmentEndDate IS NULL
AND L.IsDeleted = 0
AND L.TaskBoardId IS NOT NULL
AND PL.ContainmentEndDate IS NULL

GO
/****** Object:  View [dbo].[vw_dim_Current_CardType]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [dbo].[vw_dim_Current_CardType] as

--Selects the current record for each CardType

SELECT 
	[DimRowId]
      ,[Id]
      ,[Name]
      ,[BoardId]
      ,[IsCardType]
      ,[IsTaskType]
      ,[IsDefaultTaskType]
      ,[StartUserId]
      ,[EndUserID]
      ,[ContainmentStartDate]
      ,[ContainmentEndDate]
      ,[EntityExceptionId]
      ,[StartDateKey]
      ,[StartTimeKey]
      ,[EndDateKey]
      ,[EndTimeKey]
      ,[DurationSeconds]
      ,[IsApproximate]
FROM [dbo].[dim_CardTypes] CT
WHERE CT.ContainmentEndDate IS NULL
AND CT.IsApproximate = 0 


GO
/****** Object:  View [dbo].[vw_dim_Current_ClassOfService]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [dbo].[vw_dim_Current_ClassOfService] as

--Selects the current record for each class of service (Custom Icon)

SELECT
	[DimRowId]
      ,[Id]
      ,[Title]
      ,[BoardId]
      ,[IsDeleted]
      ,[StartUserId]
      ,[EndUserID]
      ,[ContainmentStartDate]
      ,[ContainmentEndDate]
      ,[EntityExceptionId]
      ,[StartDateKey]
      ,[StartTimeKey]
      ,[EndDateKey]
      ,[EndTimeKey]
      ,[DurationSeconds]
      ,[IsApproximate]
FROM [dbo].[dim_ClassOfService] CS
WHERE CS.ContainmentEndDate IS NULL
AND CS.IsApproximate = 0 
AND CS.IsDeleted = 0


GO
/****** Object:  View [dbo].[vw_dim_Current_TaskCard]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [dbo].[vw_dim_Current_TaskCard] as

--Selects the current record for each card that is not deleted 
-- and in a lane that is not deleted 
--and that does not belong to a board that is deleted or archive

SELECT
	C.[DimRowId]
      ,C.[Id]
      ,C.[Version]
      ,C.[IsDeleted]
      ,C.[Title]
      ,C.[Description]
      ,C.[Active]
      ,C.[Size]
      ,C.[IsBlocked]
      ,C.[BlockReason]
      ,C.[CreatedOn]
      ,C.[DueDate]
      ,C.[Priority]
      ,C.[Index]
      ,C.[ExternalSystemName]
      ,C.[ExternalSystemUrl]
      ,C.[ExternalCardID]
      ,C.[Tags]
      ,C.[LaneId]
      ,C.[ClassOfServiceId]
      ,C.[TypeId]
      ,C.[CurrentTaskBoardId]
      ,C.[DrillThroughBoardId]
      ,C.[ParentCardId]
      ,C.[BlockStateChangeDate]
      ,C.[LastMove]
      ,C.[AttachmentsCount]
      ,C.[LastAttachment]
      ,C.[CommentsCount]
      ,C.[LastComment]
      ,C.[LastActivity]
      ,C.[DateArchived]
      ,C.[StartDate]
      ,C.[ActualStartDate]
      ,C.[ActualFinishDate]
      ,C.[StartDateKey]
      ,C.[StartTimeKey]
      ,C.[EndDateKey]
      ,C.[EndTimeKey]
      ,C.[DurationSeconds]
      ,C.[StartUserId]
      ,C.[EndUserId]
      ,C.[IsApproximate]
      ,C.[EntityExceptionId]
      ,C.[ContainmentStartDate]
      ,C.[ContainmentEndDate]
	   ,L.OrganizationId
	   ,CT.Name AS CardTypeTitle
	   ,CS.Title AS CustomIconTitle
	   ,L.BoardId
	   ,L.BoardTitle
	   ,L.Title AS LaneTitle
FROM [dbo].[dim_Card] C
JOIN [dbo].[vw_dim_Current_TaskboardLane] L ON C.LaneId = L.Id
LEFT JOIN [dbo].[vw_dim_Current_CardType] CT ON CT.Id = C.TypeId
LEFT JOIN [dbo].[vw_dim_Current_ClassOfService] CS ON CS.Id = C.ClassOfServiceId
WHERE C.ContainmentEndDate IS NULL
AND C.IsApproximate = 0 
AND C.IsDeleted = 0


GO
/****** Object:  View [dbo].[vw_dim_Current_Lane]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [dbo].[vw_dim_Current_Lane] as

--Selects the current record for each lane lane on a board that is not deleted 
--and that does not belong to a board that is deleted or archive

SELECT 
	L.[DimRowId]
      ,L.[Id]
      ,L.[IsDeleted]
      ,L.[Title]
      ,L.[Description]
      ,L.[LaneTypeId]
      ,L.[Orientation]
      ,L.[Type]
      ,L.[Active]
      ,L.[CreationDate]
      ,L.[CardLimit]
      ,L.[Width]
      ,L.[Index]
      ,L.[BoardId]
      ,L.[TaskBoardId]
      ,L.[ParentLaneId]
      ,L.[ActivityId]
      ,L.[CardContextId]
      ,L.[IsDrillthroughDoneLane]
      ,L.[IsDefaultDropLane]
      ,L.[StartDateKey]
      ,L.[StartTimeKey]
      ,L.[EndDateKey]
      ,L.[EndTimeKey]
      ,L.[DurationSeconds]
      ,L.[StartUserId]
      ,L.[EndUserId]
      ,L.[IsApproximate]
      ,L.[EntityExceptionId]
      ,L.[ContainmentStartDate]
      ,L.[ContainmentEndDate]
      ,B.OrganizationId
	  ,B.Title AS BoardTitle
	  ,PL.Title AS ParentLaneTitle
	  ,CASE WHEN L.[ParentLaneId] IS NOT NULL THEN PL.Title + ' -> ' + L.Title ELSE L.Title END AS FullLaneTitle 
	  ,CASE WHEN L.ParentLaneId IS NULL THEN 1 ELSE 0 END AS IsTopLevelLane
	  ,CASE WHEN LC.ChildLaneCount IS NULL OR LC.ChildLaneCount = 0  THEN 1 ELSE 0 END AS CanHoldCards  
	  ,CASE WHEN LC.ChildLaneCount IS NOT NULL AND LC.ChildLaneCount > 0 THEN 1 ELSE 0 END AS HasChildLanes
	  ,ISNULL(LC.ChildLaneCount,0) AS ChildLaneCount
FROM [dbo].[dim_Lane] L
JOIN [dbo].[vw_dim_Current_Board] B ON B.id = L.BoardId
LEFT JOIN [dbo].[dim_Lane] PL ON L.ParentLaneId = PL.Id
LEFT JOIN (SELECT COUNT([Id]) AS ChildLaneCount, ParentLaneId 
		   FROM [dbo].[dim_Lane] L2
		   WHERE L2.IsDeleted = 0
				AND L2.IsApproximate = 0
				AND L2.ContainmentEndDate IS NULL
				AND L2.TaskBoardId IS NULL
		   GROUP BY ParentLaneId) LC ON LC.ParentLaneId = L.Id
WHERE L.ContainmentEndDate IS NULL
AND L.IsDeleted = 0
AND L.TaskBoardId IS NULL 
AND PL.ContainmentEndDate IS NULL
AND (PL.IsDeleted = 0 OR PL.IsDeleted IS NULL)
AND PL.TaskBoardId IS NULL 


GO
/****** Object:  View [dbo].[vw_dim_Current_Card]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [dbo].[vw_dim_Current_Card] as

--Selects the current record for each card that is not deleted 
-- and in a lane that is not deleted 
--and that does not belong to a board that is deleted or archive

SELECT
	C.[DimRowId]
      ,C.[Id]
      ,C.[Version]
      ,C.[IsDeleted]
      ,C.[Title]
      ,C.[Description]
      ,C.[Active]
      ,C.[Size]
      ,C.[IsBlocked]
      ,(CASE WHEN C.[IsBlocked] = 1 THEN C.[BlockReason] ELSE NULL END) AS [BlockReason]
	  ,(CASE WHEN C.[IsBlocked] = 1 THEN NULL ELSE C.[BlockReason] END) AS [UnblockReason]
      ,C.[CreatedOn]
      ,C.[DueDate]
      ,C.[Priority]
      ,C.[Index]
      ,C.[ExternalSystemName]
      ,C.[ExternalSystemUrl]
      ,C.[ExternalCardID]
      ,C.[Tags]
      ,C.[LaneId]
      ,C.[ClassOfServiceId]
      ,C.[TypeId]
      ,C.[CurrentTaskBoardId]
      ,C.[DrillThroughBoardId]
      ,C.[ParentCardId]
      ,C.[BlockStateChangeDate]
      ,C.[LastMove]
      ,C.[AttachmentsCount]
      ,C.[LastAttachment]
      ,C.[CommentsCount]
      ,C.[LastComment]
      ,C.[LastActivity]
      ,C.[DateArchived]
      ,C.[StartDate]
      ,C.[ActualStartDate]
      ,C.[ActualFinishDate]
      ,C.[StartDateKey]
      ,C.[StartTimeKey]
      ,C.[EndDateKey]
      ,C.[EndTimeKey]
      ,C.[DurationSeconds]
      ,C.[StartUserId]
      ,C.[EndUserId]
      ,C.[IsApproximate]
      ,C.[EntityExceptionId]
      ,C.[ContainmentStartDate]
      ,C.[ContainmentEndDate]
	   ,L.OrganizationId
	   ,CT.Name AS CardTypeTitle
	   ,CS.Title AS CustomIconTitle
	   ,L.BoardId
	   ,L.BoardTitle
	   ,L.Title AS LaneTitle
	   ,L.FullLaneTitle
	   ,(CASE L.LaneTypeId WHEN 0 THEN 'Active' WHEN 1 THEN 'Backlog' WHEN 2 THEN 'Archive' END) AS CurrentLaneType
	   ,'https://' + O.HostName + '.leankit.com/Boards/View/' + CONVERT(NVARCHAR(MAX), L.BoardId) + '/' + (CASE WHEN C.ParentCardId IS NULL THEN CONVERT(NVARCHAR(MAX), C.Id) ELSE '?cardPath=' + CONVERT(NVARCHAR(MAX), PL.BoardId) + '|' + CONVERT(NVARCHAR(MAX), PC.Id) + '/' + CONVERT(NVARCHAR(MAX), C.Id) END) AS Permalink 
FROM [dbo].[dim_Card] C
JOIN [dbo].[vw_dim_Current_Lane] L ON C.LaneId = L.Id
JOIN [dbo].[dim_Organization] O ON O.Id = L.OrganizationId
LEFT JOIN [dbo].[vw_dim_Current_CardType] CT ON CT.Id = C.TypeId
LEFT JOIN [dbo].[vw_dim_Current_ClassOfService] CS ON CS.Id = C.ClassOfServiceId
LEFT JOIN [dim_Card] PC ON PC.Id = C.ParentCardId
LEFT JOIN [vw_dim_Current_Lane] PL ON PC.LaneId = PL.Id
WHERE C.ContainmentEndDate IS NULL
AND O.EndDateKey IS NULL
AND L.ContainmentEndDate IS NULL
AND C.IsApproximate = 0 
AND C.IsDeleted = 0
AND CT.ContainmentEndDate IS NULL
AND CS.ContainmentEndDate IS NULL
AND PC.ContainmentEndDate IS NULL
AND PL.ContainmentEndDate IS NULL
 

GO
/****** Object:  View [dbo].[vw_dim_Current_User_All]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [dbo].[vw_dim_Current_User_All] as

--All users including deleted and disabled users

SELECT
	[DimRowId]
      ,[Id]
      ,[Username]
      ,[EmailAddress]
      ,[Administrator]
      ,[Enabled]
      ,[FirstName]
      ,[LastName]
      ,[TimeZone]
      ,[DateFormat]
      ,[IsAccountOwner]
      ,[IsDeleted]
      ,[IsSystemAdministrator]
      ,[SendMeEmailCommunicationsAbout]
      ,[KeepMeUpdatedOf]
      ,[LeanKitCommunicationsRead]
      ,[IsSupportAccount]
      ,[OrganizationId]
      ,[CreationDate]
      ,[LastLoginAttempt]
      ,[LoginAttemptCount]
      ,[AccountLockTime]
      ,[LastAccess]
      ,[BoardCreator]
      ,[ImageVisualization]
      ,[ExternalUserName]
      ,[StartDateKey]
      ,[StartTimeKey]
      ,[EndDateKey]
      ,[EndTimeKey]
      ,[DurationSeconds]
      ,[StartUserId]
      ,[EndUserId]
      ,[IsApproximate]
      ,[EntityExceptionId]
      ,[ContainmentStartDate]
      ,[ContainmentEndDate]
FROM [dbo].[dim_User] U
WHERE U.ContainmentEndDate IS NULL
AND U.IsApproximate = 0 


GO
/****** Object:  View [dbo].[vw_fact_CardBlockContainmentPeriod]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [dbo].[vw_fact_CardBlockContainmentPeriod] as

--Selects all the applicable blocked periods of current cards

SELECT 
	  BP.[ID]
    , BP.[CardID]
    , BP.[StartDateKey]
    , BP.[StartTimeKey]
    , BP.[EndDateKey]
    , BP.[EndTimeKey]
    , BP.[DurationSeconds]
    , BP.[IsApproximate]
    , BP.[EntityExceptionId]
    , BP.[ContainmentStartDate]
    , BP.[ContainmentEndDate]
    , C.OrganizationId
	, C.[Title] AS CardTitle
	, C.[Size] AS CardSize
	, C.[Priority]
	, C.[ClassOfServiceId] AS CustomIconId
	, C.[CustomIconTitle]
	, C.[TypeId] AS CardTypeId
	, C.[CardTypeTitle]
	, C.[BoardId]
	, C.[BoardTitle]
	, BP.[StartUserId] AS BlockedByUserId
	, BU.[EmailAddress] AS BlockedByUserEmailAddress
	, BU.LastName + ', ' + BU.FirstName AS BlockedByUserFullName
	, BP.[EndUserId] AS UnblockedByUserId
	, UBU.[EmailAddress] AS UnblockedByUserEmailAddress
	, UBU.LastName + ', ' + UBU.FirstName AS UnblockedByUserName
	, DATEDIFF(DAY,BP.[ContainmentStartDate],ISNULL(BP.[ContainmentEndDate],GETUTCDATE())) AS TotalDurationDays
    , DATEDIFF(HOUR,BP.[ContainmentStartDate],ISNULL(BP.[ContainmentEndDate],GETUTCDATE())) AS TotalDurationHours
    , DATEDIFF(DAY, BP.[ContainmentStartDate], ISNULL(BP.[ContainmentEndDate],GETUTCDATE())) - (DATEDIFF(WEEK, BP.[ContainmentStartDate], ISNULL(BP.[ContainmentEndDate],GETUTCDATE())) * 2) - 
		CASE WHEN DATEPART(dw,BP.[ContainmentStartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,ISNULL(BP.[ContainmentEndDate],GETUTCDATE())) = 1 THEN 1 ELSE 0 END TotalDurationDaysMinusWeekends
	, C.BlockReason
	, C.UnblockReason
	--, [BlockedLane].LaneID AS [Blocked Lane ID]
	--, [BlockedLane].LaneTitle AS [Blocked Lane Title]
	--, [BlockedLane].FullLaneTitle AS [Blocked Lane Full Title]
	--, [UnblockedLane].LaneID AS [Unblocked Lane ID]
	--, [UnblockedLane].LaneTitle AS [Unblocked Lane Title]
	--, [UnblockedLane].FullLaneTitle AS [Unblocked Lane Full Title]
FROM [dbo].[fact_CardBlockContainmentPeriod] BP
	JOIN [dbo].[vw_dim_Current_Card] C ON C.Id = BP.CardID
	LEFT JOIN [dbo].[vw_dim_Current_User_All] BU ON BU.Id = BP.StartUserId
	LEFT JOIN [dbo].[vw_dim_Current_User_All] UBU ON UBU.Id = BP.EndUserId
	--LEFT JOIN [dbo].[vw_fact_CardLaneContainmentPeriod] [BlockedLane] 
	--	ON [BlockedLane].[CardID] = [C].[Id] 
	--	AND [BP].[ContainmentStartDate] BETWEEN
	--	[BlockedLane].[ContainmentStartDate]
	--	AND (CASE WHEN [BlockedLane].[ContainmentEndDate] IS NULL THEN GETUTCDATE() ELSE [BlockedLane].[ContainmentEndDate] END)
	--LEFT JOIN [dbo].[vw_fact_CardLaneContainmentPeriod] [UnblockedLane]
	--	ON [UnblockedLane].[CardID] = [C].[Id]
	--	AND [BP].[ContainmentEndDate] BETWEEN
	--	[UnblockedLane].[ContainmentStartDate]
	--	AND (CASE WHEN [UnblockedLane].[ContainmentEndDate] IS NULL THEN GETUTCDATE() ELSE [UnblockedLane].[ContainmentEndDate] END)
WHERE BP.IsApproximate = 0


GO
/****** Object:  View [dbo].[vw_fact_CardLaneContainmentPeriod]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [dbo].[vw_fact_CardLaneContainmentPeriod] as

--Selects all the applicable blocked periods of current cards

SELECT 
	LCP.[ID]
      ,LCP.[CardID]
      ,LCP.[LaneID]
      ,LCP.[StartDateKey]
      ,LCP.[StartTimeKey]
      ,LCP.[EndDateKey]
      ,LCP.[EndTimeKey]
      ,LCP.[DurationSeconds]
      ,LCP.[StartOrdinal]
      ,LCP.[EndOrdinal]
      ,LCP.[IsApproximate]
      ,LCP.[EntityExceptionId]
      ,LCP.[ContainmentStartDate]
      ,LCP.[ContainmentEndDate]
       , C.OrganizationId
	   , C.[Title] AS CardTitle
	   , C.[Size] AS CardSize
	   , C.[Priority]
	   , C.[ClassOfServiceId] AS CustomIconId
	   , C.[CustomIconTitle]
	   , C.[TypeId] AS CardTypeId
	   , C.[CardTypeTitle]
	   , C.[BoardId]
	   , C.[BoardTitle]
	   , LCP.[StartUserId] AS MovedIntoByUserId
	   , L.Title AS LaneTitle
	   , L.FullLaneTitle
	   , MIU.[EmailAddress] AS MovedIntoByUserEmailAddress
	   , MIU.LastName + ', ' + MIU.FirstName AS MovedIntoByUserFullName
	   , LCP.[EndUserId] AS MovedOutByUserId
	   , MIU.[EmailAddress] AS MovedOutByUserEmailAddress
	   , MIU.LastName + ', ' + MIU.FirstName AS MovedOutByUserName
	   , DATEDIFF(DAY,LCP.[ContainmentStartDate],ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) AS TotalDurationDays
       , DATEDIFF(HOUR,LCP.[ContainmentStartDate],ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) AS TotalDurationHours
       , DATEDIFF(DAY, LCP.[ContainmentStartDate], ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) - (DATEDIFF(WEEK, LCP.[ContainmentStartDate], ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) * 2) - 
			CASE WHEN DATEPART(dw,LCP.[ContainmentStartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) = 1 THEN 1 ELSE 0 END TotalDurationDaysMinusWeekends
FROM [dbo].[fact_CardLaneContainmentPeriod] LCP
	JOIN [dbo].[vw_dim_Current_Card] C ON C.Id = LCP.CardID
	JOIN [dbo].[vw_dim_Current_Lane] L ON L.Id = LCP.LaneID
	LEFT JOIN [dbo].[vw_dim_Current_User_All] MIU ON MIU.Id = LCP.StartUserId
	LEFT JOIN [dbo].[vw_dim_Current_User_All] MOU ON MOU.Id = LCP.EndUserId  
WHERE LCP.IsApproximate = 0


GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_CardBlockedPeriods]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnCustomReporting_CardBlockedPeriods] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	WITH cte AS
	(
		SELECT CardID AS [Card ID]
		, ContainmentStartDate AS [Blocked From Date]
		, ContainmentEndDate AS [Blocked To Date]
		, CardTitle AS [Card Title]
		, CardSize AS [Card Size]
		, (CASE [Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Card Priority]
		, CustomIconId AS [Custom Icon ID]
		, CustomIconTitle AS [Custom Icon Title]
		, CardTypeId AS [Card Type ID]
		, CardTypeTitle AS [Card Type Title]
		, BoardId AS [Board ID]
		, BoardTitle AS [Board Title]
		, BlockedByUserId AS [Blocked By User ID]
		, BlockedByUserEmailAddress AS [Blocked By User Email Address]
		, BlockedByUserFullName AS [Blocked By User Full Name]
		, UnblockedByUserId AS [Unblocked By User ID]
		, UnblockedByUserEmailAddress AS [Unblocked By User Email Address]
		, UnblockedByUserName AS [Unblocked By User Full Name]
		, TotalDurationDays AS [Total Blocked Duration (Days)]
		, TotalDurationHours AS [Total Blocked Duration (Hours)]
		, TotalDurationDaysMinusWeekends AS [Total Blocked Duration Minus Weekends (Days)]
		, BlockReason AS [Blocked Reason]
		, UnblockReason AS [Unblocked Reason]
		--,[Blocked Lane ID]
		--,[Blocked Lane Title]
		--,[Blocked Lane Full Title]
		--,[Unblocked Lane ID]
		--,[Unblocked Lane Title]
		--,[Unblocked Lane Full Title]
		,ROW_NUMBER() OVER(PARTITION BY [CardId], [StartDateKey] ORDER BY [ContainmentStartDate] desc) rn
		FROM [dbo].[vw_fact_CardBlockContainmentPeriod]
		WHERE OrganizationId = @organizationId
	)
	SELECT 
	  [Card ID]
	, [Blocked From Date]
	, [Blocked To Date]
	, [Card Title]
	, [Card Size]
	, [Card Priority]
	, [Custom Icon ID]
	, [Custom Icon Title]
	, [Card Type ID]
	, [Card Type Title]
	, [Board ID]
	, [Board Title]
	, [Blocked By User ID]
	, [Blocked By User Email Address]
	, [Blocked By User Full Name]
	, [Unblocked By User ID]
	, [Unblocked By User Email Address]
	, [Unblocked By User Full Name]
	, [Total Blocked Duration (Days)]
	, [Total Blocked Duration (Hours)]
	, [Total Blocked Duration Minus Weekends (Days)]

	FROM cte WHERE rn = 1
) --Each card should only appear once per day, either blocked or unblocked




GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_CardLaneContainmentPeriods]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnCustomReporting_CardLaneContainmentPeriods] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	WITH cte AS
	(
		SELECT  CardID AS [Card ID]
		, CardTitle AS [Card Title]
		, CardSize AS [Card Size]
		, (CASE [Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Card Priority]
		, CustomIconId AS [Custom Icon ID]
		, CustomIconTitle AS [Custom Icon Title]
		, CardTypeId AS [Card Type ID]
		, CardTypeTitle AS [Card Type Title]
		, LaneID AS [Lane ID]
		, LaneTitle AS [Lane Title]
		, FullLaneTitle AS [Full Lane Title]
		, BoardId AS [Board ID]
		, BoardTitle AS [Board Title]
		, ContainmentStartDate AS [Containment Start Date]
		, ContainmentEndDate AS [Containment End Date]
		, MovedIntoByUserId AS [Moved Into By User ID]
		, MovedIntoByUserEmailAddress AS [Moved Into By User Email Address]
		, MovedIntoByUserFullName AS [Moved Into By User Full Name]
		, MovedOutByUserId AS [Moved Out By User ID]
		, MovedOutByUserEmailAddress AS [Moved Out By User Email Address]
		, MovedOutByUserName AS [Moved Out By User Full Name]
		, TotalDurationDays AS [Total Containment Duration (Days)]
		, TotalDurationHours AS [Total Containment Duration (Hours)]
		, TotalDurationDaysMinusWeekends AS [Total Containment Duration Minus Weekends (Days)]
		, ROW_NUMBER() OVER(PARTITION BY [CardId], [StartDateKey] ORDER BY [ContainmentStartDate] desc) rn
		FROM [dbo].[vw_fact_CardLaneContainmentPeriod]
		WHERE OrganizationId = @organizationId
	--Same here, each card should only be in 1 lane per day, the last lane it was in
	) SELECT
	  [Card ID]
	, [Card Title]
	, [Card Size]
	, [Card Priority]
	, [Custom Icon ID]
	, [Custom Icon Title]
	, [Card Type ID]
	, [Card Type Title]
	, [Lane ID]
	, [Lane Title]
	, [Full Lane Title]
	, [Board ID]
	, [Board Title]
	, [Containment Start Date]
	, [Containment End Date]
	, [Moved Into By User ID]
	, [Moved Into By User Email Address]
	, [Moved Into By User Full Name]
	, [Moved Out By User ID]
	, [Moved Out By User Email Address]
	, [Moved Out By User Full Name]
	, [Total Containment Duration (Days)]
	, [Total Containment Duration (Hours)]
	, [Total Containment Duration Minus Weekends (Days)]
	FROM cte WHERE rn = 1
)


GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_Current_Boards]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnCustomReporting_Current_Boards] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	SELECT B.[Id] AS [Board ID]
      ,[Title] AS [Board Title]
      ,ISNULL([Description],'') AS [Description]
      ,B.[CreationDate] AS [Creation Date]
      ,[BoardCreatorId] AS [Board Creator ID]
      ,BoardCreator AS [Board Creator]
  FROM [dbo].[vw_dim_Current_Board] B
  WHERE OrganizationId = @organizationId
)


GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_Current_Cards]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnCustomReporting_Current_Cards] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	SELECT C.[Id] AS [Card ID]
      ,C.[Title] AS [Card Title]
      ,ISNULL(C.[Description],'') AS [Description]
      ,[Size] AS [Card Size]
      ,CONVERT(BIT, [IsBlocked]) AS [Is Card Blocked]
      ,ISNULL([BlockReason],'') AS [Current Blocked Reason]
      ,[CreatedOn] AS [Creation Date]
      ,[DueDate] AS [Planned Finish Date]
      ,[StartDate] AS [Planned Start Date]
      , (CASE [Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Priority]
      ,C.[Index] AS [Current Lane Position]
      ,ISNULL([ExternalSystemName],'') AS [Card Link Name]
      ,ISNULL([ExternalSystemUrl],'') AS [Card Link Url]
      ,ISNULL([ExternalCardID],'') AS [External Card ID]
      ,ISNULL([Tags],'') AS [Tags]
      ,[LaneId] AS [Current Lane ID]
	  ,LaneTitle AS [Current Lane Title]
	  ,FullLaneTitle AS [Current Full Lane Title]
      ,BoardId AS [Current Board ID]
	  ,BoardTitle AS [Current Board Title]
      ,[ClassOfServiceId] AS [Custom Icon ID]
	  ,CustomIconTitle AS [Custom Icon Title]
      ,[TypeId] AS [Card Type ID]
	  ,CardTypeTitle AS [Card Type Title]
      ,[DrillThroughBoardId] AS [Connection Board ID]
      ,[ParentCardId] AS [Parent Card ID]
      ,[LastMove] AS [Last Moved Date]
      ,[AttachmentsCount] AS [Attachments Count]
      ,[LastAttachment] AS [Last Attachment Date]
      ,[CommentsCount] AS [Comments Count]
      ,[LastComment] AS [Last Comment Date]
      ,[LastActivity] AS [Last Activity Date]
      ,[DateArchived] AS [Archived Date]
      ,[ActualStartDate] AS [Last Actual Start Date]
      ,[ActualFinishDate] AS [Last Actual Finish Date]
      ,DATEDIFF(DAY,[ActualStartDate],[ActualFinishDate]) AS [Actual Duration (Days)]
      ,DATEDIFF(HOUR,[ActualStartDate],[ActualFinishDate]) AS [Actual Duration (Hours)]
      ,DATEDIFF(DAY, [ActualStartDate], [ActualFinishDate]) - (DATEDIFF(WEEK, [ActualStartDate], [ActualFinishDate]) * 2) - 
			CASE WHEN DATEPART(dw,[ActualStartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,[ActualFinishDate] ) = 1 THEN 1 ELSE 0 END AS [Actual Duration Minus Weekends (Days)]
	  ,DATEDIFF(DAY,[StartDate],[DueDate]) AS [Planned Duration (Days)]
      ,DATEDIFF(HOUR,[StartDate],[DueDate]) AS [Planned Duration (Hours)]
      ,DATEDIFF(DAY, [StartDate],[DueDate]) - (DATEDIFF(WEEK, [StartDate],[DueDate]) * 2) - 
			CASE WHEN DATEPART(dw,[StartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,[DueDate] ) = 1 THEN 1 ELSE 0 END AS [Planned Duration Minus Weekends (Days)]
	  ,[CurrentLaneType] AS [Current Lane Type]
	  ,[Permalink]
  FROM [dbo].[vw_dim_Current_Card] C
  WHERE OrganizationId = @organizationId
)



GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_Current_Lanes]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnCustomReporting_Current_Lanes] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	SELECT L.[Id] AS [Lane ID]
      ,L.[Title] AS [Lane Title]
	  ,FullLaneTitle AS [Full Lane Title]
      ,L.[Description] AS [Lane Policy]
      ,CASE L.[LaneTypeId]
		WHEN 0 THEN 'Backlog'
		WHEN 1 THEN 'OnBoard'
		WHEN 2 THEN 'Archive'
	   END AS [Lane Class]
      ,CASE WHEN L.[Orientation] = 0 THEN 'Vertical' ELSE 'Horizontal' END AS [Lane Orientation]
      ,CASE L.[Type]
		WHEN 99 THEN 'Not Set'
		WHEN 1 THEN 'Ready'
		WHEN 2 THEN 'In Process'
		WHEN 3 THEN 'Complete'
		END AS [Lane Type]
      ,L.[CreationDate] AS [Creation Date]
      ,L.[CardLimit] AS [WIP Limit]
      ,L.[Width] AS [Lane Width]
      ,L.[Index] AS [Lane Position]
      ,L.[BoardId] AS [Board ID]
	  ,L.BoardTitle AS [Board Title]
      ,L.[ParentLaneId] AS [Parent Lane ID]
	  ,L.ParentLaneTitle AS [Parent Lane Title]
      ,L.[ActivityId] AS [Activity ID]
      ,L.[IsDrillthroughDoneLane] AS [Is Completed Lane]
      ,L.[IsDefaultDropLane] AS [Is Default Drop Lane]
	  ,CONVERT(BIT, IsTopLevelLane) AS [Is Top Level Lane]
	  ,CONVERT(BIT, CanHoldCards) AS [Can Hold Cards]  
	  ,CONVERT(BIT, HasChildLanes) AS [Has Child Lanes]
	  ,ChildLaneCount AS [Child Lane Count]
  FROM [dbo].[vw_dim_Current_Lane] L
  WHERE OrganizationId = @organizationId
)





GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_Current_TaskboardLanes]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnCustomReporting_Current_TaskboardLanes] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	SELECT L.[Id] AS [Lane ID]
      ,L.[Title] AS [Lane Title]
      ,CASE L.[Type]
		WHEN 99 THEN 'Not Set'
		WHEN 1 THEN 'Ready'
		WHEN 2 THEN 'In Process'
		WHEN 3 THEN 'Complete'
		END AS [Lane Type]
      ,L.[CreationDate] AS [Creation Date]
      ,L.[Index] AS [Lane Position]
      ,L.[BoardId] AS [Board ID]
	  ,L.BoardTitle AS [Board Title]
  FROM [dbo].[vw_dim_Current_TaskboardLane] L
  WHERE OrganizationId = @organizationId
)





GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_Current_TaskCards]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnCustomReporting_Current_TaskCards] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	SELECT C.[Id] AS [Card ID]
      ,C.[Title] AS [Card Title]
      ,ISNULL(C.[Description],'') AS [Description]
      ,[Size] AS [Card Size]
      ,[IsBlocked] AS [Is Card Blocked]
      ,ISNULL([BlockReason],'') AS [Current Blocked Reason]
      ,[CreatedOn] AS [Creation Date]
      ,[DueDate] AS [Planned Finish Date]
	  ,(CASE [Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Priority]
      ,C.[Index] AS [Current Lane Position]
      ,ISNULL([ExternalSystemName],'') AS [Card Link Name]
      ,ISNULL([ExternalSystemUrl],'') AS [Card Link Url]
      ,ISNULL([ExternalCardID],'') AS [External Card ID]
      ,ISNULL([Tags],'') AS [Tags]
      ,[LaneId] AS [Current Lane ID]
	  ,LaneTitle AS [Current Lane Title]
      ,[ClassOfServiceId] AS [Custom Icon ID]
	  ,CustomIconTitle AS [Custom Icon Title]
      ,[TypeId] AS [Card Type ID]
	  ,CardTypeTitle AS [Card Type Title]
      ,[LastMove] AS [Last Moved Date]
      ,[AttachmentsCount] AS [Attachments Count]
      ,[LastAttachment] AS [Last Attachment Date]
      ,[CommentsCount] AS [Comments Count]
      ,[LastComment] AS [Last Comment Date]
      ,[LastActivity] AS [Last Activity Date]
      ,[StartDate] AS [Planned Start Date]
      ,[ActualStartDate] AS [Last Actual Start Date]
      ,[ActualFinishDate] AS [Last Actual Finish Date]
      ,DATEDIFF(DAY,[StartDate],[DueDate]) AS [Planned Duration (Days)]
      ,DATEDIFF(HOUR,[StartDate],[DueDate]) AS [Planned Duration (Hours)]
      ,DATEDIFF(DAY, [StartDate],[DueDate]) - (DATEDIFF(WEEK, [StartDate],[DueDate]) * 2) - 
			CASE WHEN DATEPART(dw,[StartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,[DueDate] ) = 1 THEN 1 ELSE 0 END AS [Planned Duration Minus Weekends (Days)]
	 FROM [dbo].[vw_dim_Current_TaskCard] C
  WHERE OrganizationId = @organizationId
)


GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_Current_Users]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnCustomReporting_Current_Users] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	SELECT [Id] AS [User ID]
      ,[EmailAddress] AS [Email Address]
      ,[Administrator] AS [Is Account Administrator]
      ,[Enabled] AS [Is Enabled]
      ,[FirstName] AS [First Name]
      ,[LastName] AS [Last Name]
      ,[TimeZone] AS [Time Zone]
      ,[DateFormat] AS [Date Format]
      ,[CreationDate] AS [Creation Date]
      ,[LastAccess] AS [Last Access Date]
      ,[BoardCreator] AS [Is Board Creator]
  FROM [dbo].[vw_dim_Current_User] U
  WHERE OrganizationId = @organizationId
  AND U.IsSupportAccount IN (NULL, 0)
)




GO
/****** Object:  View [dbo].[vw_fact_UserAssignmentContainmentPeriod]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE view [dbo].[vw_fact_UserAssignmentContainmentPeriod] as
	SELECT
	[a].[ID]
	,[a].[CardID]
	,[u].[Id] AS [ToUserID]
	,([u].[FirstName] + ', ' + [u].[LastName]) AS [ToUserName]
	,[u].[EmailAddress] AS [ToUserEmail]
	,[a].[StartDateKey]
	,[a].[StartTimeKey]
	,[a].[EndDateKey]
	,[a].[EndTimeKey]
	,[a].[DurationSeconds]
	,[a].[StartUserId]
	,[a].[EndUserId]
	,[a].[IsApproximate]
	,[a].[EntityExceptionId]
	,[a].[ContainmentStartDate]
	,[a].[ContainmentEndDate]
	,[b].[OrganizationId]
	,[c].[Title] AS CardTitle
	,[c].[Size] AS CardSize
	,[c].[Priority]
	,[c].[ClassOfServiceId] AS CustomIconId
	,ISNULL([cos].[Title], 'Not Set') AS [CustomIconTitle]
	,[c].[TypeId] AS CardTypeId
	,[ct].[Name] AS [CardTypeTitle]
	,[b].[Id] AS BoardId
	,[b].[Title] AS BoardTitle
	,(Assigned.LastName + ', ' + Assigned.FirstName) AS AssignedUserFullName
	,[AU].[EmailAddress] AS AssignedByUserEmailAddress
	,([AU].[LastName] + ', ' + [AU].[FirstName]) AS AssignedByUserFullName
	,[UU].[EmailAddress] AS UnassignedByUserEmailAddress
	,[UU].LastName + ', ' + UU.FirstName AS UnassignedByUserName
	,DATEDIFF(DAY,[a].[ContainmentStartDate],ISNULL([a].[ContainmentEndDate],GETUTCDATE())) AS TotalDurationDays
    ,DATEDIFF(HOUR,[a].[ContainmentStartDate],ISNULL([a].[ContainmentEndDate],GETUTCDATE())) AS TotalDurationHours
    ,DATEDIFF(DAY, [a].[ContainmentStartDate], ISNULL([a].[ContainmentEndDate],GETUTCDATE())) - (DATEDIFF(WEEK, [a].[ContainmentStartDate], ISNULL([a].[ContainmentEndDate],GETUTCDATE())) * 2) - 
			CASE WHEN DATEPART(dw, [a].[ContainmentStartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,ISNULL([a].[ContainmentEndDate],GETUTCDATE())) = 1 THEN 1 ELSE 0 END TotalDurationDaysMinusWeekends
	FROM [fact_UserAssignmentContainmentPeriod] [a]
	JOIN [dim_User] [u] ON [u].[Id] = [a].[ToUserID]
	JOIN [dim_Card] [c] ON [c].[Id] = [a].[CardID]
	JOIN [dim_Lane] [l] ON [l].[Id] = [c].[LaneId]
	JOIN [dim_Board] [b] ON [b].[Id] = [l].[BoardId]
	LEFT JOIN [dim_ClassOfService] [cos] ON [cos].[Id] = [c].[ClassOfServiceId]
	JOIN [dim_CardTypes] [ct] ON [ct].[Id] = [c].[TypeId]
	LEFT JOIN [dbo].[dim_User] AU ON AU.Id = [a].StartUserId
	LEFT JOIN [dbo].[dim_User] UU ON UU.Id = [a].EndUserId 
	LEFT JOIN [dbo].[dim_User] Assigned ON UU.Id = [a].ToUserID 
	WHERE 
	[a].[ContainmentEndDate] IS NULL
	AND [u].[ContainmentEndDate] IS NULL
	AND [c].[ContainmentEndDate] IS NULL
	AND [l].[ContainmentEndDate] IS NULL
	AND [b].[ContainmentEndDate] IS NULL
	AND [AU].[ContainmentEndDate] IS NULL
	AND [UU].[ContainmentEndDate] IS NULL
	AND [Assigned].[ContainmentEndDate] IS NULL
	AND [a].[IsApproximate] = 0
	AND [u].[IsApproximate] = 0
	AND [c].[IsApproximate] = 0
	AND [l].[IsApproximate] = 0
	AND [b].[IsApproximate] = 0
	AND [b].[IsArchived] = 0
	AND [c].[IsDeleted] = 0
	AND [l].[IsDeleted] = 0
	AND [b].[IsDeleted] = 0
	AND [l].[TaskBoardId] IS NULL


GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_UserAssignmentContainmentPeriods]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fnCustomReporting_UserAssignmentContainmentPeriods] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	WITH cte AS
	(
	  SELECT 
	  CardID AS [Card ID]
		, ToUserID AS [Assigned User ID]
		, AssignedUserFullName AS [Assigned User Full Name]
		, ToUserEmail AS [Assigned User Email Address]
		, StartUserId AS [Assigned By User ID]
		, EndUserId AS [Unassigned By User ID]
		, ContainmentStartDate AS [Assigned From Date]
		, ContainmentEndDate AS [Assigned To Date]
		, OrganizationId AS [Organization ID]
		, CardTitle AS [Card Title]
		, CardSize AS [Card Size]
		,(CASE [Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Priority]
		, CustomIconId AS [Custom Icon ID]
		, CustomIconTitle AS [Custom Icon Title]
		, CardTypeId AS [Card Type ID]
		, CardTypeTitle AS [Card Type Title]
		, BoardId AS [Board ID]
		, BoardTitle AS [Board Title]
		, AssignedByUserEmailAddress AS [Assigned By User Email Address]
		, AssignedByUserFullName AS [Assigned By User Full Name]
		, UnassignedByUserEmailAddress AS [Unassigned By User Email Address]
		, UnassignedByUserName AS [Unassigned By User Full Name]
		, TotalDurationDays AS [Total Duration (Days)]
		, TotalDurationHours AS [Total Duration (Hours)]
		, TotalDurationDaysMinusWeekends AS [Total Duration Minus Weekends (Days)]
		, ROW_NUMBER() OVER(PARTITION BY [CardID], [ToUserID], [StartDateKey] ORDER BY [ContainmentStartDate] desc) rn
		  FROM [dbo].[vw_fact_UserAssignmentContainmentPeriod]
		  WHERE OrganizationId = @organizationId
	  ) SELECT
	    [Card ID]
	  , [Assigned User ID]
	  , [Assigned User Full Name]
	  , [Assigned User Email Address]
	  , [Assigned By User ID]
	  , [Unassigned By User ID]
	  , [Assigned From Date]
	  , [Assigned To Date]
	  , [Organization ID]
	  , [Card Title]
	  , [Card Size]
	  , [Priority]
	  , [Custom Icon ID]
	  , [Custom Icon Title]
	  , [Card Type ID]
	  , [Card Type Title]
	  , [Board ID]
	  , [Board Title]
	  , [Assigned By User Email Address]
	  , [Assigned By User Full Name]
	  , [Unassigned By User Email Address]
	  , [Unassigned By User Full Name]
	  , [Total Duration (Days)]
	  , [Total Duration (Hours)]
	  , [Total Duration Minus Weekends (Days)]
	   FROM cte WHERE rn = 1
)


GO
/****** Object:  UserDefinedFunction [dbo].[_udtf_DimRowId_Card_Current]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Chris Gundersen
-- Create date: 21-Jun-2016
-- Description:	Gets the DimRowID values for "current"
--				cards from dim_Card with appropriate
--				filters applied
-- =============================================
CREATE FUNCTION [dbo].[_udtf_DimRowId_Card_Current] 
(
	@organizationId BIGINT
	, @maxDaysOfAnalyticsDays INT = 365
	, @numberOfDaysUntilCabinet INT = 14
)
RETURNS TABLE 
AS
RETURN 
(
	SELECT MAX(dC.[DimRowId]) AS [DimRowId]
	FROM [dbo].[dim_Card] dC
	WHERE dC.[ContainmentEndDate] IS NULL
	AND dC.[IsApproximate] = 0
	AND dC.[IsDeleted] = 0
	GROUP BY dC.[Id]
)

GO
/****** Object:  UserDefinedFunction [dbo].[fn_API_Card_Export]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fn_API_Card_Export]
(
	@organizationId BIGINT
	, @userId		BIGINT
)
RETURNS TABLE
AS
RETURN
(
	SELECT 
	   [C].[Id] AS [Card ID]
	   ,ISNULL([C].[ExternalCardID],'') AS [External Card ID]
      ,[C].[Title] AS [Card Title]
	  ,[CT].[Name] AS [Card Type]
      ,[C].[Size] AS [Card Size]
	  , (CASE [C].[Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Priority]
	  ,[COS].[ClassOfServiceTitle] AS [Custom Icon]
	  , CASE WHEN [C].[IsBlocked] = 1 THEN 'Y' ELSE 'N' END AS [Is Card Blocked]
      ,ISNULL(REPLACE(REPLACE([C].[BlockReason], CHAR(13), '\r'), CHAR(10), '\n'),' ') AS [Current Blocked Reason]
	  ,ISNULL([C].[ExternalSystemName],'') AS [Card External Link Name]
      ,ISNULL([C].[ExternalSystemUrl],'') AS [Card External Link Url]
	  ,[C].[CreatedOn] AS [Creation Date]
	  ,[C].[StartDate] AS [Planned Start Date]
	  ,[C].[ActualStartDate] AS [Actual Start Date]
	  ,[C].[DueDate] AS [Planned Finish Date]
	  ,[C].[ActualFinishDate] AS [Actual Finish Date]
	  ,[C].[AttachmentsCount] AS [Attachments Count]
      ,[C].[LastAttachment] AS [Last Attachment Date]
      ,[C].[CommentsCount] AS [Comments Count]
      ,[C].[LastComment] AS [Last Comment Date]
      ,[C].[LastActivity] AS [Last Activity Date]
      ,[C].[DateArchived] AS [Archived Date]
	  ,[C].[LastMove] AS [Last Moved Date]
	  ,[C].[LaneId] AS [Current Lane ID]
	  ,[L].[Title] AS [Current Lane Title]
	  ,(CASE WHEN [L].[ParentLaneId] IS NULL THEN NULL ELSE [PL].[LaneTitle] END) AS [Parent Lane Title]
	  ,(CASE [L].[Type] WHEN 99 THEN 'Not Set' WHEN 1 THEN 'Ready' WHEN 2 THEN 'In Process' WHEN 3 THEN 'Completed' END) AS [Current Lane Type]
	  ,[B].[Id] AS [Current Board ID]
	  ,[B].[Title] AS [Current Board Title]
  FROM 
	[dim_Board] [B] WITH (NOLOCK)
	INNER JOIN [dbo].[fn_Util_Get_BoardIds_for_Org_and_User](@organizationId, @userId) AS [boardsForUser]
		ON [boardsForUser].[BoardId] = [B].[Id]
	JOIN [dim_Lane] [L] WITH (NOLOCK) ON [L].[BoardId] = [B].[Id]
	JOIN [dim_Card] [C] WITH (NOLOCK) ON [C].[LaneId] = [L].[Id]
	JOIN [dim_CardTypes] [CT] WITH (NOLOCK) ON [CT].[Id] = [C].[TypeId]
	LEFT JOIN (
		SELECT DISTINCT [classofservice].[Id] AS [ClassOfServiceId], [classofservice].[Title] AS [ClassOfServiceTitle]
		FROM [dbo].[dim_ClassOfService] AS [classofservice] WITH (NOLOCK)
		INNER JOIN [dbo].[dim_Board] AS db WITH (NOLOCK)
			ON [classofservice].[BoardId] = db.[Id]
		WHERE db.[OrganizationId] = @organizationId
		AND db.[IsDeleted] = 0
		AND [classofservice].[ContainmentEndDate] IS NULL
		AND ([classofservice].[IsApproximate] IS NULL OR [classofservice].[IsApproximate] = 0)
	) [COS] ON [COS].[ClassOfServiceId] = [C].[ClassOfServiceId]
	LEFT JOIN (
		SELECT DISTINCT [dl].[Id] AS [LaneId], [dl].[Title] AS [LaneTitle]
		FROM [dbo].[dim_Lane] AS dl WITH (NOLOCK)
		INNER JOIN [dbo].[dim_Board] db WITH (NOLOCK)
			ON dl.[BoardId] = db.[Id]
		WHERE db.[OrganizationId] = @organizationId
		AND dl.[ContainmentEndDate] IS NULL
		AND (dl.[IsApproximate] IS NOT NULL OR dl.[IsApproximate] = 0)
	) [PL] ON [PL].[LaneId] = [L].[ParentLaneId]
  WHERE [B].[OrganizationId] = @organizationId
	AND [B].[ContainmentEndDate] IS NULL
	AND [B].[IsApproximate] = 0
	AND [B].[IsDeleted] = 0
	AND [L].[ContainmentEndDate] IS NULL
	AND [L].[IsApproximate] = 0
	AND [L].[TaskBoardId] IS NULL
	AND [L].[IsDeleted] = 0
	AND [C].[ContainmentEndDate] IS NULL
	AND [C].[IsApproximate] = 0
	AND [C].[IsDeleted] = 0
	AND [CT].[ContainmentEndDate] IS NULL
	AND [CT].[IsApproximate] = 0  
)

GO
/****** Object:  UserDefinedFunction [dbo].[fn_API_Card_Lane_History]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE FUNCTION [dbo].[fn_API_Card_Lane_History]
(
	@organizationId BIGINT
	, @userId		BIGINT
)
RETURNS TABLE
AS
RETURN
(
	SELECT 
	   [C].[Id] AS [Card ID]
	   ,ISNULL([C].[ExternalCardID],'') AS [External Card ID]
      ,[C].[Title] AS [Card Title]
	  ,[fCLCP].[ContainmentStartDate] AS [Lane Entry Date]
	  ,[fCLCP].[ContainmentEndDate] AS [Lane Exit Date]
	  ,[L].[Id] AS [Lane ID]
	  ,[L].[Title] AS [Lane Title]
	  ,[B].[Id] AS [Board ID]
	  ,[B].[Title] AS [Board Title]
  FROM 
	[dim_Board] [B] WITH (NOLOCK)
	INNER JOIN [dbo].[fn_Util_Get_BoardIds_for_Org_and_User](@organizationId, @userId) AS [boardsForUser]
		ON [boardsForUser].[BoardId] = [B].[Id]
	JOIN [dim_Lane] [L] WITH (NOLOCK) ON [L].[BoardId] = [B].[Id]
	JOIN [dim_Card] [C] WITH (NOLOCK) ON [C].[LaneId] = [L].[Id]
	JOIN [fact_CardLaneContainmentPeriod] fCLCP
		ON [C].[Id] = fCLCP.[CardID]
		AND [L].[Id] = fCLCP.[LaneID]
  WHERE [B].[OrganizationId] = @organizationId
	AND [B].[ContainmentEndDate] IS NULL
	AND [B].[IsApproximate] = 0
	AND [B].[IsDeleted] = 0
	AND [L].[ContainmentEndDate] IS NULL
	AND [L].[IsApproximate] = 0
	AND [L].[TaskBoardId] IS NULL
	AND [L].[IsDeleted] = 0
	AND [C].[ContainmentEndDate] IS NULL
	AND [C].[IsApproximate] = 0
	AND [C].[IsDeleted] = 0
)

GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_CardLaneContainmentPeriods_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[fnCustomReporting_CardLaneContainmentPeriods_0_2] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	WITH cte AS
	(
		SELECT
		  [LCP].[CardID] AS [Card ID]
		, [C].[Title] AS [Card Title]
		, [C].[Size] AS [Card Size]
		, (CASE [C].[Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Card Priority]
		, [C].[ClassOfServiceId] AS [Custom Icon ID]
		, [COS].[Title] AS [Custom Icon Title]
		, [C].[TypeId] AS [Card Type ID]
		, [CT].[Name] AS [Card Type Title]
		, [LCP].[LaneId] AS [Lane ID]
		, [L].[Title] AS [Lane Title]
		, CASE [L].[LaneTypeId]
			WHEN 0 THEN 'Backlog'
			WHEN 1 THEN 'OnBoard'
			WHEN 2 THEN 'Archive'
		   END AS [Lane Class]
		, CASE [L].[Type]
			WHEN 99 THEN 'Not Set'
			WHEN 1 THEN 'Ready'
			WHEN 2 THEN 'In Process'
			WHEN 3 THEN 'Completed'
			END AS [Lane Type]
		,(CASE WHEN [L].[ParentLaneId] IS NULL THEN [L].[Title] ELSE [PL].[Title] + ' -> ' + [L].[Title] END) AS [Full Lane Title]
		, [B].[Id] AS [Board ID]
		, [B].[Title] AS [Board Title]
		, [LCP].[ContainmentStartDate] AS [Containment Start Date]
		, [LCP].[ContainmentEndDate] AS [Containment End Date]
		, [LCP].[StartUserId] AS [Moved Into By User ID]
		, [MIU].[EmailAddress] AS [Moved Into By User Email Address]
		, ([MIU].[LastName] + ', ' + [MIU].[FirstName]) AS [Moved Into By User Full Name]
		, [LCP].[EndUserId] AS [Moved Out By User ID]
		, [MOU].[EmailAddress] AS [Moved Out By User Email Address]
		, ([MOU].[LastName] + ', ' + [MOU].[FirstName]) AS [Moved Out By User Full Name]
		, DATEDIFF(DAY,LCP.[ContainmentStartDate],ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) AS [Total Containment Duration (Days)]
		, DATEDIFF(HOUR,LCP.[ContainmentStartDate],ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) AS [Total Containment Duration (Hours)]
		, DATEDIFF(DAY, LCP.[ContainmentStartDate], ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) - (DATEDIFF(WEEK, LCP.[ContainmentStartDate], ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) * 2) - 
			(CASE WHEN DATEPART(dw,LCP.[ContainmentStartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) = 1 THEN 1 ELSE 0 END) AS [Total Containment Duration Minus Weekends (Days)]
		, ROW_NUMBER() OVER(PARTITION BY [LCP].[CardId], [LCP].[StartDateKey] ORDER BY [LCP].[ContainmentStartDate] desc) rn
		FROM
			[fact_CardLaneContainmentPeriod] [LCP]
			JOIN [dim_Card] [C] ON [C].[Id] = [LCP].[CardId]
			JOIN [dim_Lane] [L] ON [L].[Id] = [LCP].[LaneId]
			JOIN [dim_Board] [B] ON [B].[Id] = [L].[BoardId]
			JOIN [dim_Organization] [O] ON [O].[Id] = [B].[OrganizationId]
			JOIN [dim_CardTypes] [CT] ON [CT].[Id] = [C].[TypeId]
			LEFT JOIN [dim_ClassOfService] [COS] ON [COS].[Id] = [C].[ClassOfServiceId]
			LEFT JOIN [dim_Lane] [PL] ON [PL].[Id] = [L].[ParentLaneId]
			JOIN [dim_User] [MIU] ON [MIU].[Id] = [LCP].[StartUserId]
			LEFT JOIN [dim_User] [MOU] ON [MOU].[Id] = [LCP].[EndUserId]
		WHERE [O].[Id] = @organizationId
			AND [O].[ContainmentEndDate] IS NULL
			AND [O].[IsApproximate] = 0
			AND [B].[ContainmentEndDate] IS NULL
			AND [B].[IsApproximate] = 0 
			AND [L].[ContainmentEndDate] IS NULL
			AND [L].[IsApproximate] = 0
			AND [L].[TaskBoardId] IS NULL
			AND [C].[ContainmentEndDate] IS NULL
			AND [C].[IsApproximate] = 0
			AND [CT].[ContainmentEndDate] IS NULL
			AND [CT].[IsApproximate] = 0
			AND [COS].[ContainmentEndDate] IS NULL
			AND ([COS].[IsApproximate] IS NULL OR [COS].[IsApproximate] = 0)
			AND [PL].[ContainmentEndDate] IS NULL
			AND ([PL].[IsApproximate] IS NULL OR [PL].[IsApproximate] = 0)
			AND [LCP].[IsApproximate] = 0
			AND [MIU].[ContainmentEndDate] IS NULL
			AND [MIU].[IsApproximate] = 0
			AND [MOU].[ContainmentEndDate] IS NULL
			AND ([MOU].[IsApproximate] IS NULL OR [MOU].[IsApproximate] = 0)
		)
		SELECT
		  [Card ID]
		, [Card Title]
		, [Card Size]
		, [Card Priority]
		, [Custom Icon ID]
		, [Custom Icon Title]
		, [Card Type ID]
		, [Card Type Title]
		, [Lane ID]
		, [Lane Title]
		, [Lane Type]
		, [Lane Class]
		, [Full Lane Title]
		, [Board ID]
		, [Board Title]
		, [Containment Start Date]
		, [Containment End Date]
		, [Moved Into By User ID]
		, [Moved Into By User Email Address]
		, [Moved Into By User Full Name]
		, [Moved Out By User ID]
		, [Moved Out By User Email Address]
		, [Moved Out By User Full Name]
		, [Total Containment Duration (Days)]
		, [Total Containment Duration (Hours)]
		, [Total Containment Duration Minus Weekends (Days)]
		FROM cte WHERE rn = 1
)

GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_CardLaneContainmentPeriods_0_2_byBoard]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[fnCustomReporting_CardLaneContainmentPeriods_0_2_byBoard] 
(	
	@organizationId BIGINT
	, @boardId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	WITH cte AS
	(
		SELECT
		  [LCP].[CardID] AS [Card ID]
		, [C].[Title] AS [Card Title]
		, [C].[Size] AS [Card Size]
		, (CASE [C].[Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Card Priority]
		, [C].[ClassOfServiceId] AS [Custom Icon ID]
		, [COS].[Title] AS [Custom Icon Title]
		, [C].[TypeId] AS [Card Type ID]
		, [CT].[Name] AS [Card Type Title]
		, [LCP].[LaneId] AS [Lane ID]
		, [L].[Title] AS [Lane Title]
		, CASE [L].[LaneTypeId]
			WHEN 0 THEN 'Backlog'
			WHEN 1 THEN 'OnBoard'
			WHEN 2 THEN 'Archive'
		   END AS [Lane Class]
		, CASE [L].[Type]
			WHEN 99 THEN 'Not Set'
			WHEN 1 THEN 'Ready'
			WHEN 2 THEN 'In Process'
			WHEN 3 THEN 'Completed'
			END AS [Lane Type]
		,(CASE WHEN [L].[ParentLaneId] IS NULL THEN [L].[Title] ELSE [PL].[Title] + ' -> ' + [L].[Title] END) AS [Full Lane Title]
		, [B].[Id] AS [Board ID]
		, [B].[Title] AS [Board Title]
		, [LCP].[ContainmentStartDate] AS [Containment Start Date]
		, [LCP].[ContainmentEndDate] AS [Containment End Date]
		, [LCP].[StartUserId] AS [Moved Into By User ID]
		, [MIU].[EmailAddress] AS [Moved Into By User Email Address]
		, ([MIU].[LastName] + ', ' + [MIU].[FirstName]) AS [Moved Into By User Full Name]
		, [LCP].[EndUserId] AS [Moved Out By User ID]
		, [MOU].[EmailAddress] AS [Moved Out By User Email Address]
		, ([MOU].[LastName] + ', ' + [MOU].[FirstName]) AS [Moved Out By User Full Name]
		, DATEDIFF(DAY,LCP.[ContainmentStartDate],ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) AS [Total Containment Duration (Days)]
		, DATEDIFF(HOUR,LCP.[ContainmentStartDate],ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) AS [Total Containment Duration (Hours)]
		, DATEDIFF(DAY, LCP.[ContainmentStartDate], ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) - (DATEDIFF(WEEK, LCP.[ContainmentStartDate], ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) * 2) - 
			(CASE WHEN DATEPART(dw,LCP.[ContainmentStartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) = 1 THEN 1 ELSE 0 END) AS [Total Containment Duration Minus Weekends (Days)]
		, ROW_NUMBER() OVER(PARTITION BY [LCP].[CardId], [LCP].[StartDateKey] ORDER BY [LCP].[ContainmentStartDate] DESC) rn
		FROM
			[fact_CardLaneContainmentPeriod] [LCP]
			JOIN [dim_Card] [C] ON [C].[Id] = [LCP].[CardId]
			JOIN [dim_Lane] [L] ON [L].[Id] = [LCP].[LaneId]
			JOIN [dim_Board] [B] ON [B].[Id] = [L].[BoardId]
			JOIN [dim_Organization] [O] ON [O].[Id] = [B].[OrganizationId]
			JOIN [dim_CardTypes] [CT] ON [CT].[Id] = [C].[TypeId]
			LEFT JOIN [dim_ClassOfService] [COS] ON [COS].[Id] = [C].[ClassOfServiceId]
			LEFT JOIN [dim_Lane] [PL] ON [PL].[Id] = [L].[ParentLaneId]
			JOIN [dim_User] [MIU] ON [MIU].[Id] = [LCP].[StartUserId]
			LEFT JOIN [dim_User] [MOU] ON [MOU].[Id] = [LCP].[EndUserId]
		WHERE [O].[Id] = @organizationId
			AND [B].[Id] = @boardId
			AND [O].[ContainmentEndDate] IS NULL
			AND [O].[IsApproximate] = 0
			AND [B].[ContainmentEndDate] IS NULL
			AND [B].[IsApproximate] = 0 
			AND [B].[IsDeleted] = 0
			AND [L].[ContainmentEndDate] IS NULL
			AND [L].[IsApproximate] = 0
			AND [L].[TaskBoardId] IS NULL
			AND [C].[ContainmentEndDate] IS NULL
			AND [C].[IsApproximate] = 0
			AND [C].[IsDeleted] = 0
			AND [CT].[ContainmentEndDate] IS NULL
			AND [CT].[IsApproximate] = 0
			AND [COS].[ContainmentEndDate] IS NULL
			AND ([COS].[IsApproximate] IS NULL OR [COS].[IsApproximate] = 0)
			AND [PL].[ContainmentEndDate] IS NULL
			AND ([PL].[IsApproximate] IS NULL OR [PL].[IsApproximate] = 0)
			AND [LCP].[IsApproximate] = 0
			AND [MIU].[ContainmentEndDate] IS NULL
			AND [MIU].[IsApproximate] = 0
			AND [MOU].[ContainmentEndDate] IS NULL
			AND ([MOU].[IsApproximate] IS NULL OR [MOU].[IsApproximate] = 0)
		)
		SELECT
		  [Card ID]
		, [Card Title]
		, [Card Size]
		, [Card Priority]
		, [Custom Icon ID]
		, [Custom Icon Title]
		, [Card Type ID]
		, [Card Type Title]
		, [Lane ID]
		, [Lane Title]
		, [Lane Type]
		, [Lane Class]
		, [Full Lane Title]
		, [Board ID]
		, [Board Title]
		, [Containment Start Date]
		, [Containment End Date]
		, [Moved Into By User ID]
		, [Moved Into By User Email Address]
		, [Moved Into By User Full Name]
		, [Moved Out By User ID]
		, [Moved Out By User Email Address]
		, [Moved Out By User Full Name]
		, [Total Containment Duration (Days)]
		, [Total Containment Duration (Hours)]
		, [Total Containment Duration Minus Weekends (Days)]
		FROM cte WHERE rn = 1
)





GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_Current_Boards_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO

CREATE FUNCTION [dbo].[fnCustomReporting_Current_Boards_0_2] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	SELECT 
	[B].[Id] AS [Board ID]
    ,[B].[Title] AS [Board Title]
    ,ISNULL([B].[Description],'') AS [Description]
    ,[B].[CreationDate] AS [Creation Date]
    ,[B].[BoardCreatorId] AS [Board Creator ID]
    ,[U].[EmailAddress] AS [Board Creator]
  FROM [dbo].[dim_Board] [B]
  JOIN [dbo].[udtf_CurrentBoardsInOrg_0_2](@organizationId) [CB] ON [CB].[DimRowId] = [B].[DimRowId]
  LEFT JOIN [dbo].[udtf_CurrentUsersInOrg_0_2](@organizationId) [U] ON [B].[BoardCreatorId] = [U].[UserId]
  WHERE [B].[Id] IS NOT NULL
)


GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_Current_CardDescriptions_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



CREATE FUNCTION [dbo].[fnCustomReporting_Current_CardDescriptions_0_2] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	SELECT 
	   [C].[Id] AS [Card ID]
      ,[C].[Title] AS [Card Title]
      ,(CASE WHEN [C].[Description] IS NULL THEN '' ELSE [C].[Description] END) AS [Description]
      ,ISNULL([C].[ExternalCardID],'') AS [External Card ID]
    FROM [dim_Card] [C]
    LEFT OUTER JOIN [dim_Lane] [L] ON [C].[LaneId] = [L].[Id]
	LEFT OUTER JOIN [dim_Board] [B] on [L].[BoardId] = [B].[Id]
	--LEFT OUTER JOIN [dim_CardTypes] [CT] ON [C].[TypeId] = [CT].[Id]
  WHERE [B].[OrganizationId] = @organizationId
  	AND [B].[ContainmentEndDate] IS NULL
	AND [B].[IsApproximate] = 0
	AND [B].[IsDeleted] = 0
	AND [B].[IsArchived] = 0
	AND [L].[ContainmentEndDate] IS NULL
	AND [L].[IsApproximate] = 0
	AND [L].[TaskBoardId] IS NULL
	AND [L].[IsDeleted] = 0
	AND [C].[ContainmentEndDate] IS NULL
	AND [C].[IsApproximate] = 0
	AND [C].[IsDeleted] = 0
	--AND [CT].[ContainmentEndDate] IS NULL
	--AND [CT].[IsApproximate] = 0  
)




GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_Current_Cards_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO

CREATE FUNCTION [dbo].[fnCustomReporting_Current_Cards_0_2]
(
	@organizationId BIGINT
)
RETURNS TABLE
AS
RETURN
(
	SELECT 
	   [C].[Id] AS [Card ID]
      ,[C].[Title] AS [Card Title]
      ,'' AS [Description]
      ,[C].[Size] AS [Card Size]
      ,CONVERT(BIT, [C].[IsBlocked]) AS [Is Card Blocked]
      ,ISNULL([C].[BlockReason],'') AS [Current Blocked Reason]
      ,[C].[CreatedOn] AS [Creation Date]
      ,[C].[DueDate] AS [Planned Finish Date]
      ,[C].[StartDate] AS [Planned Start Date]
      , (CASE [C].[Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Priority]
      ,[C].[Index] AS [Current Lane Position]
      ,ISNULL([C].[ExternalSystemName],'') AS [Card Link Name]
      ,ISNULL([C].[ExternalSystemUrl],'') AS [Card Link Url]
      ,ISNULL([C].[ExternalCardID],'') AS [External Card ID]
      ,ISNULL([C].[Tags],'') AS [Tags]
      ,[C].[LaneId] AS [Current Lane ID]
	  ,[L].[Title] AS [Current Lane Title]
	  ,(CASE WHEN [L].[ParentLaneId] IS NULL THEN [L].[Title] ELSE [PL].[LaneTitle] + ' -> ' + [L].[Title] END) AS [Current Full Lane Title]
	  ,[B].[Id] AS [Current Board ID]
	  ,[B].[Title] AS [Current Board Title]
      ,[C].[ClassOfServiceId] AS [Custom Icon ID]
      ,[COS].[ClassOfServiceTitle] AS [Custom Icon Title]
	  ,[C].[TypeId] AS [Card Type ID]
	  ,[CT].[Name] AS [Card Type Title]
	  ,[C].[DrillThroughBoardId] AS [Connection Board ID]
      ,[C].[ParentCardId] AS [Parent Card ID]
      ,[C].[LastMove] AS [Last Moved Date]
      ,[C].[AttachmentsCount] AS [Attachments Count]
      ,[C].[LastAttachment] AS [Last Attachment Date]
      ,[C].[CommentsCount] AS [Comments Count]
      ,[C].[LastComment] AS [Last Comment Date]
      ,[C].[LastActivity] AS [Last Activity Date]
      ,[C].[DateArchived] AS [Archived Date]
      ,[C].[ActualStartDate] AS [Last Actual Start Date]
      ,[C].[ActualFinishDate] AS [Last Actual Finish Date]
      ,DATEDIFF(DAY,[C].[ActualStartDate],[C].[ActualFinishDate]) AS [Actual Duration (Days)]
      ,DATEDIFF(HOUR,[C].[ActualStartDate],[C].[ActualFinishDate]) AS [Actual Duration (Hours)]
      ,DATEDIFF(DAY, [C].[ActualStartDate], [C].[ActualFinishDate]) - (DATEDIFF(WEEK, [C].[ActualStartDate], [C].[ActualFinishDate]) * 2) - 
			CASE WHEN DATEPART(dw,[C].[ActualStartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,[C].[ActualFinishDate] ) = 1 THEN 1 ELSE 0 END AS [Actual Duration Minus Weekends (Days)]
	  ,DATEDIFF(DAY,[C].[StartDate],[C].[DueDate]) AS [Planned Duration (Days)]
      ,DATEDIFF(HOUR,[C].[StartDate],[C].[DueDate]) AS [Planned Duration (Hours)]
      ,DATEDIFF(DAY, [C].[StartDate],[C].[DueDate]) - (DATEDIFF(WEEK, [StartDate],[DueDate]) * 2) - 
			CASE WHEN DATEPART(dw,[C].[StartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,[C].[DueDate] ) = 1 THEN 1 ELSE 0 END AS [Planned Duration Minus Weekends (Days)]
	   ,(CASE [L].[Type] WHEN 99 THEN 'Not Set' WHEN 1 THEN 'Ready' WHEN 2 THEN 'In Process' WHEN 3 THEN 'Completed' END) AS [Current Lane Type]
	   ,(CASE [L].[LaneTypeId] WHEN 0 THEN 'Backlog' WHEN 1 THEN 'OnBoard' WHEN 2 THEN 'Archive' END) AS [Current Lane Class]
  FROM 
	[dim_Board] [B] WITH (NOLOCK)
	JOIN [dim_Lane] [L] WITH (NOLOCK) ON [L].[BoardId] = [B].[Id]
	JOIN [dim_Card] [C] WITH (NOLOCK) ON [C].[LaneId] = [L].[Id]
	JOIN [dim_CardTypes] [CT] WITH (NOLOCK) ON [CT].[Id] = [C].[TypeId]
	LEFT JOIN (
		SELECT DISTINCT [classofservice].[Id] AS [ClassOfServiceId], [classofservice].[Title] AS [ClassOfServiceTitle]
		FROM [dbo].[dim_ClassOfService] AS [classofservice] WITH (NOLOCK)
		INNER JOIN [dbo].[dim_Board] AS db WITH (NOLOCK)
			ON [classofservice].[BoardId] = db.[Id]
		WHERE db.[OrganizationId] = @organizationId
		AND db.[IsDeleted] = 0
		AND [classofservice].[ContainmentEndDate] IS NULL
		AND ([classofservice].[IsApproximate] IS NULL OR [classofservice].[IsApproximate] = 0)
	) [COS] ON [COS].[ClassOfServiceId] = [C].[ClassOfServiceId]
	LEFT JOIN (
		SELECT DISTINCT [dl].[Id] AS [LaneId], [dl].[Title] AS [LaneTitle]
		FROM [dbo].[dim_Lane] AS dl WITH (NOLOCK)
		INNER JOIN [dbo].[dim_Board] db WITH (NOLOCK)
			ON dl.[BoardId] = db.[Id]
		WHERE db.[OrganizationId] = @organizationId
		AND dl.[ContainmentEndDate] IS NULL
		AND (dl.[IsApproximate] IS NOT NULL OR dl.[IsApproximate] = 0)
	) [PL] ON [PL].[LaneId] = [L].[ParentLaneId]
  WHERE [B].[OrganizationId] = @organizationId
	AND [B].[ContainmentEndDate] IS NULL
	AND [B].[IsApproximate] = 0
	AND [B].[IsDeleted] = 0
	AND [L].[ContainmentEndDate] IS NULL
	AND [L].[IsApproximate] = 0
	AND [L].[TaskBoardId] IS NULL
	AND [L].[IsDeleted] = 0
	AND [C].[ContainmentEndDate] IS NULL
	AND [C].[IsApproximate] = 0
	AND [C].[IsDeleted] = 0
	AND [CT].[ContainmentEndDate] IS NULL
	AND [CT].[IsApproximate] = 0  
)

GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_Current_Lanes_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[fnCustomReporting_Current_Lanes_0_2] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	SELECT [L].[Id] AS [Lane ID]
      ,[L].[Title] AS [Lane Title]
	  ,[CL].[FullLaneTitle] AS [Full Lane Title]
      ,[L].[Description] AS [Lane Policy]
      ,CASE [L].[LaneTypeId]
		WHEN 0 THEN 'Backlog'
		WHEN 1 THEN 'OnBoard'
		WHEN 2 THEN 'Archive'
	   END AS [Lane Class]
      ,CASE WHEN [L].[Orientation] = 0 THEN 'Vertical' ELSE 'Horizontal' END AS [Lane Orientation]
      ,CASE [L].[Type]
		WHEN 99 THEN 'Not Set'
		WHEN 1 THEN 'Ready'
		WHEN 2 THEN 'In Process'
		WHEN 3 THEN 'Completed'
		END AS [Lane Type]
      ,[L].[CreationDate] AS [Creation Date]
      ,[L].[CardLimit] AS [WIP Limit]
      ,[L].[Width] AS [Lane Width]
      ,[L].[Index] AS [Lane Position]
      ,[L].[BoardId] AS [Board ID]
	  ,[CL].BoardTitle AS [Board Title]
      ,[L].[ParentLaneId] AS [Parent Lane ID]
	  ,[PL].[Title] AS [Parent Lane Title]
      ,[L].[ActivityId] AS [Activity ID]
      ,[L].[IsDrillthroughDoneLane] AS [Is Completed Lane]
      ,[L].[IsDefaultDropLane] AS [Is Default Drop Lane]
	  ,CONVERT(BIT, CASE WHEN [L].ParentLaneId IS NULL THEN 1 ELSE 0 END) AS [Is Top Level Lane]
	  ,CONVERT(BIT, CASE WHEN [LC].ChildLaneCount IS NULL OR LC.ChildLaneCount = 0  THEN 1 ELSE 0 END) AS [Can Hold Cards]  
	  ,CONVERT(BIT, CASE WHEN [LC].ChildLaneCount IS NOT NULL AND LC.ChildLaneCount > 0 THEN 1 ELSE 0 END) AS [Has Child Lanes]
	  ,[ChildLaneCount] AS [Child Lane Count]
  FROM [dbo].[dim_Lane] [L]
  JOIN [dbo].[udtf_CurrentLanesInOrg_0_2](@organizationId) [CL] ON [CL].[DimRowId] = [L].[DimRowId]
  LEFT JOIN [dbo].[udtf_CurrentLanesInOrg_0_2](@organizationId) [PL] ON [PL].[LaneId] = [CL].[ParentLaneId]
  LEFT JOIN (SELECT COUNT([Id]) AS ChildLaneCount, ParentLaneId 
		   FROM [dbo].[dim_Lane] L2
		   WHERE L2.IsDeleted = 0
				AND L2.IsApproximate = 0
				AND L2.ContainmentEndDate IS NULL
				AND L2.TaskBoardId IS NULL
		   GROUP BY ParentLaneId) LC ON LC.ParentLaneId = L.Id
  WHERE [CL].[OrganizationId] = @organizationId
  AND [L].[TaskBoardId] IS NULL
)

GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_Current_TaskboardLanes_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[fnCustomReporting_Current_TaskboardLanes_0_2] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	SELECT 
	[L].[Id] AS [Lane ID]
    ,[L].[Title] AS [Lane Title]
    ,CASE [L].[Type]
		WHEN 99 THEN 'Not Set'
		WHEN 1 THEN 'Ready'
		WHEN 2 THEN 'In Process'
		WHEN 3 THEN 'Completed'
		END AS [Lane Type]
    ,[L].[CreationDate] AS [Creation Date]
    ,[L].[Index] AS [Lane Position]
    ,[L].[BoardId] AS [Board ID]
	,[CTBL].[BoardTitle] AS [Board Title]
  FROM [dbo].[dim_Lane] [L]
  JOIN [dbo].[udtf_CurrentTaskboardLanesInOrg_0_2](@organizationId) [CTBL] ON [CTBL].[DimRowId] = [L].[DimRowId]
)

GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_Current_TaskCards_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE FUNCTION [dbo].[fnCustomReporting_Current_TaskCards_0_2] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	SELECT 
	   [C].[Id] AS [Card ID]
      ,[C].[Title] AS [Card Title]
      ,'' AS [Description]
      ,[C].[Size] AS [Card Size]
      ,CONVERT(BIT, [C].[IsBlocked]) AS [Is Card Blocked]
      ,ISNULL([C].[BlockReason],'') AS [Current Blocked Reason]
      ,[C].[CreatedOn] AS [Creation Date]
      ,[C].[DueDate] AS [Planned Finish Date]
      ,[C].[StartDate] AS [Planned Start Date]
      , (CASE [C].[Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Priority]
      ,[C].[Index] AS [Current Lane Position]
      ,ISNULL([C].[ExternalSystemName],'') AS [Card Link Name]
      ,ISNULL([C].[ExternalSystemUrl],'') AS [Card Link Url]
      ,ISNULL([C].[ExternalCardID],'') AS [External Card ID]
      ,ISNULL([C].[Tags],'') AS [Tags]
      ,[C].[LaneId] AS [Current Lane ID]
	  ,[L].[Title] AS [Current Lane Title]
      ,[B].[Id] AS [Current Board ID]
	  ,[B].[Title] AS [Current Board Title]
      ,[C].[ClassOfServiceId] AS [Custom Icon ID]
	  ,[COS].[Title] AS [Custom Icon Title]
      ,[C].[TypeId] AS [Card Type ID]
	  ,[CT].[Name] AS [Card Type Title]
      ,[CC].[Id] AS [Container Card ID]
	  ,[CC].[Title] AS [Container Card Title]
      ,[C].[LastMove] AS [Last Moved Date]
      ,[C].[AttachmentsCount] AS [Attachments Count]
      ,[C].[LastAttachment] AS [Last Attachment Date]
      ,[C].[CommentsCount] AS [Comments Count]
      ,[C].[LastComment] AS [Last Comment Date]
      ,[C].[LastActivity] AS [Last Activity Date]
      ,[C].[ActualStartDate] AS [Last Actual Start Date]
      ,[C].[ActualFinishDate] AS [Last Actual Finish Date]
      ,DATEDIFF(DAY,[C].[ActualStartDate],[C].[ActualFinishDate]) AS [Actual Duration (Days)]
      ,DATEDIFF(HOUR,[C].[ActualStartDate],[C].[ActualFinishDate]) AS [Actual Duration (Hours)]
      ,DATEDIFF(DAY, [C].[ActualStartDate], [C].[ActualFinishDate]) - (DATEDIFF(WEEK, [C].[ActualStartDate], [C].[ActualFinishDate]) * 2) - 
			CASE WHEN DATEPART(dw,[C].[ActualStartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,[C].[ActualFinishDate] ) = 1 THEN 1 ELSE 0 END AS [Actual Duration Minus Weekends (Days)]
	  ,DATEDIFF(DAY,[C].[StartDate],[C].[DueDate]) AS [Planned Duration (Days)]
      ,DATEDIFF(HOUR,[C].[StartDate],[C].[DueDate]) AS [Planned Duration (Hours)]
      ,DATEDIFF(DAY, [C].[StartDate],[C].[DueDate]) - (DATEDIFF(WEEK, [C].[StartDate],[C].[DueDate]) * 2) - 
			CASE WHEN DATEPART(dw,[C].[StartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,[C].[DueDate] ) = 1 THEN 1 ELSE 0 END AS [Planned Duration Minus Weekends (Days)]
	  ,CASE [L].[LaneTypeId]
		WHEN 0 THEN 'Backlog'
		WHEN 1 THEN 'OnBoard'
		WHEN 2 THEN 'Archive'
	   END AS [Current Lane Class]
      ,CASE [L].[Type]
		WHEN 99 THEN 'Not Set'
		WHEN 1 THEN 'Ready'
		WHEN 2 THEN 'In Process'
		WHEN 3 THEN 'Completed'
		END AS [Current Lane Type]
    FROM [dim_Card] [C]
	LEFT OUTER JOIN [dim_Lane] [L] ON [C].[LaneId] = [L].[Id]
	LEFT OUTER JOIN [dim_Board] [B] on [L].[BoardId] = [B].[Id]
	LEFT OUTER JOIN [dim_Organization] [O] ON [B].[OrganizationId] = [O].[Id]
	LEFT OUTER JOIN [dim_CardTypes] [CT] ON [C].[TypeId] = [CT].[Id]
	LEFT OUTER JOIN [dim_ClassOfService] [COS] ON [C].[ClassOfServiceId] = [COS].[Id]
	LEFT OUTER JOIN [dim_Card] [CC] ON [L].[TaskBoardId] = [CC].[CurrentTaskBoardId]
  WHERE [O].[Id] = @organizationId
	AND [O].[ContainmentEndDate] IS NULL
	AND [O].[IsApproximate] = 0
	AND [B].[ContainmentEndDate] IS NULL
	AND [B].[IsApproximate] = 0 
	AND [L].[ContainmentEndDate] IS NULL
	AND [L].[IsApproximate] = 0
	AND [L].[TaskBoardId] IS NOT NULL
	AND [C].[ContainmentEndDate] IS NULL
	AND [C].[IsApproximate] = 0
	AND [CT].[ContainmentEndDate] IS NULL
	AND [CT].[IsApproximate] = 0
	AND [COS].[ContainmentEndDate] IS NULL
	AND ([COS].[IsApproximate] IS NULL OR [COS].[IsApproximate] = 0)
	AND [CC].[ContainmentEndDate] IS NULL
	AND [CC].[IsApproximate] = 0
)



GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_Current_Users_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[fnCustomReporting_Current_Users_0_2] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	SELECT 
	   [U].[Id] AS [User ID]
      ,[U].[EmailAddress] AS [Email Address]
      ,[U].[Administrator] AS [Is Account Administrator]
      ,[U].[Enabled] AS [Is Enabled]
      ,[U].[FirstName] AS [First Name]
      ,[U].[LastName] AS [Last Name]
      ,[U].[TimeZone] AS [Time Zone]
      ,[U].[DateFormat] AS [Date Format]
      ,[U].[CreationDate] AS [Creation Date]
      ,[U].[LastAccess] AS [Last Access Date]
      ,[U].[BoardCreator] AS [Is Board Creator]
	  FROM
	  [dbo].[dim_User] [U]
	  JOIN [dbo].[udtf_CurrentUsersInOrg_0_2](@organizationId) [CU] ON [CU].[DimRowId] = [U].[DimRowId]
	  WHERE
	  [U].[IsSupportAccount] IS NULL OR [U].[IsSupportAccount] = 0
)

GO
/****** Object:  UserDefinedFunction [dbo].[fnCustomReporting_UserAssignmentContainmentPeriods_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[fnCustomReporting_UserAssignmentContainmentPeriods_0_2] 
(	
	@organizationId BIGINT
)
RETURNS TABLE 
AS
RETURN 
(
	WITH cte AS
	(
		SELECT 
		[UAC].[CardID] AS [Card ID]
		, [UAC].[ToUserID] AS [Assigned User ID]
		, [TU].[LastName] + ', ' + [TU].[FirstName] AS [Assigned User Full Name]
		, [TU].[EmailAddress] AS [Assigned User Email Address]
		, [UAC].[StartUserId] AS [Assigned By User ID]
		, [UAC].[EndUserId] AS [Unassigned By User ID]
		, [UAC].[ContainmentStartDate] AS [Assigned From Date]
		, [UAC].[ContainmentEndDate] AS [Assigned To Date]
		, [C].[Title] AS [Card Title]
		, [C].[Size] AS [Card Size]
		, (CASE [C].[Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Priority]
		, [C].[ClassOfServiceId] AS [Custom Icon ID]
		, ISNULL([COS].[Title], '* Not Set') AS [Custom Icon Title]
		, [C].[TypeId] AS [Card Type ID]
		, [CT].[Name] AS [Card Type Title]
		, [B].[Id] AS [Board ID]
		, [B].[Title] AS [Board Title]
		, [AU].[EmailAddress] AS [Assigned By User Email Address]
		, [AU].[LastName] + ', ' + [AU].[FirstName] AS [Assigned By User Full Name]
		, [UAU].[EmailAddress] AS [Unassigned By User Email Address]
		, [UAU].[LastName] + ', ' + [UAU].[FirstName] AS [Unassigned By User Full Name]
		, DATEDIFF(DAY,[UAC].[ContainmentStartDate],ISNULL([UAC].[ContainmentEndDate],GETUTCDATE())) AS [Total Duration (Days)]
		, DATEDIFF(HOUR,[UAC].[ContainmentStartDate],ISNULL([UAC].[ContainmentEndDate],GETUTCDATE())) AS [Total Duration (Hours)]
		, DATEDIFF(DAY, [UAC].[ContainmentStartDate], ISNULL([UAC].[ContainmentEndDate],GETUTCDATE())) - (DATEDIFF(WEEK, [UAC].[ContainmentStartDate], ISNULL([UAC].[ContainmentEndDate],GETUTCDATE())) * 2) - 
			(CASE WHEN DATEPART(dw,[UAC].[ContainmentStartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,ISNULL([UAC].[ContainmentEndDate],GETUTCDATE())) = 1 THEN 1 ELSE 0 END)  AS [Total Duration Minus Weekends (Days)]
		, ROW_NUMBER() OVER(PARTITION BY [UAC].[CardId], [UAC].[ToUserID], [UAC].[StartDateKey] ORDER BY [UAC].[ContainmentStartDate] desc) rn
		FROM [fact_UserAssignmentContainmentPeriod] [UAC]
		JOIN [dim_Card] [C] ON [C].[Id] = [UAC].[CardId]
		JOIN [dim_Lane] [L] ON [L].[Id] = [C].[LaneId]
		JOIN [dim_Board] [B] ON [B].[Id] = [L].[BoardId]
		JOIN [dim_Organization] [O] ON [O].[Id] = [B].[OrganizationId]
		JOIN [dim_CardTypes] [CT] ON [CT].[Id] = [C].[TypeId]
		LEFT JOIN [dim_ClassOfService] [COS] ON [COS].[Id] = [C].[ClassOfServiceId]
		JOIN [dim_User] [AU] ON [AU].[Id] = [UAC].[StartUserId]
		LEFT JOIN [dim_User] [UAU] ON [UAU].[Id] = [UAC].[EndUserId]
		JOIN [dim_User] [TU] ON [TU].[Id] = [UAC].[ToUserId]
		WHERE [O].[Id] = @organizationId
			AND [O].[ContainmentEndDate] IS NULL
			AND [O].[IsApproximate] = 0
			AND [B].[ContainmentEndDate] IS NULL
			AND [B].[IsApproximate] = 0 
			AND [L].[ContainmentEndDate] IS NULL
			AND [L].[IsApproximate] = 0
			AND [L].[TaskBoardId] IS NULL
			AND [C].[ContainmentEndDate] IS NULL
			AND [C].[IsApproximate] = 0
			AND [CT].[ContainmentEndDate] IS NULL
			AND [CT].[IsApproximate] = 0
			AND [COS].[ContainmentEndDate] IS NULL
			AND ([COS].[IsApproximate] IS NULL OR [COS].[IsApproximate] = 0)
			AND [UAC].[IsApproximate] = 0
			AND [AU].[ContainmentEndDate] IS NULL
			AND [AU].[IsApproximate] = 0
			AND [UAU].[ContainmentEndDate] IS NULL
			AND ([UAU].[IsApproximate] IS NULL OR [UAU].[IsApproximate] = 0)
			AND [TU].[ContainmentEndDate] IS NULL
			AND [TU].[IsApproximate] = 0
	  ) SELECT
	    [cte].[Card ID]
	  , [cte].[Assigned User ID]
	  , [cte].[Assigned User Full Name]
	  , [cte].[Assigned User Email Address]
	  , [cte].[Assigned By User ID]
	  , [cte].[Unassigned By User ID]
	  , [cte].[Assigned From Date]
	  , [cte].[Assigned To Date]
	  , [cte].[Card Title]
	  , [cte].[Card Size]
	  , [cte].[Priority]
	  , [cte].[Custom Icon ID]
	  , [cte].[Custom Icon Title]
	  , [cte].[Card Type ID]
	  , [cte].[Card Type Title]
	  , [cte].[Board ID]
	  , [cte].[Board Title]
	  , [cte].[Assigned By User Email Address]
	  , [cte].[Assigned By User Full Name]
	  , [cte].[Unassigned By User Email Address]
	  , [cte].[Unassigned By User Full Name]
	  , [cte].[Total Duration (Days)]
	  , [cte].[Total Duration (Hours)]
	  , [cte].[Total Duration Minus Weekends (Days)]
	   FROM cte WHERE rn = 1
)

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_AllCardLaneContainmentPeriods_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[udtf_AllCardLaneContainmentPeriods_0_2]
(
	@organizationId BIGINT
)
RETURNS TABLE
AS
RETURN
(
	SELECT 
	LCP.[ID]
      ,LCP.[CardID]
      ,LCP.[LaneID]
      ,LCP.[StartDateKey]
      ,LCP.[StartTimeKey]
      ,LCP.[EndDateKey]
      ,LCP.[EndTimeKey]
      ,LCP.[DurationSeconds]
      ,LCP.[StartOrdinal]
      ,LCP.[EndOrdinal]
      ,LCP.[IsApproximate]
      ,LCP.[EntityExceptionId]
      ,LCP.[ContainmentStartDate]
      ,LCP.[ContainmentEndDate]
	   , C.[Title] AS CardTitle
	   , C.[Size] AS CardSize
	   , C.[Priority]
	   , C.[ClassOfServiceId] AS CustomIconId
	   , [COS].[Title] AS [CustomIconTitle]
	   , C.[TypeId] AS CardTypeId
	   , CT.Name AS [CardTypeTitle]
	   , C.[BoardId]
	   , [B].[Title] AS [BoardTitle]
	   , LCP.[StartUserId] AS MovedIntoByUserId
	   , L.Title AS LaneTitle
	   , L.FullLaneTitle
	   , MIU.[EmailAddress] AS MovedIntoByUserEmailAddress
	   , MIU.FullName AS MovedIntoByUserFullName
	   , LCP.[EndUserId] AS MovedOutByUserId
	   , MOU.[EmailAddress] AS MovedOutByUserEmailAddress
	   , MOU.FullName AS MovedOutByUserName
	   , DATEDIFF(DAY,LCP.[ContainmentStartDate],ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) AS TotalDurationDays
       , DATEDIFF(HOUR,LCP.[ContainmentStartDate],ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) AS TotalDurationHours
       , DATEDIFF(DAY, LCP.[ContainmentStartDate], ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) - (DATEDIFF(WEEK, LCP.[ContainmentStartDate], ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) * 2) - 
			CASE WHEN DATEPART(dw,LCP.[ContainmentStartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,ISNULL(LCP.[ContainmentEndDate],GETUTCDATE())) = 1 THEN 1 ELSE 0 END TotalDurationDaysMinusWeekends
FROM [dbo].[fact_CardLaneContainmentPeriod] LCP
	JOIN [dbo].[udtf_CurrentCardsInOrg_0_2](@organizationId) C ON C.CardId = LCP.CardID
	JOIN [dbo].[udtf_CurrentLanesInOrg_0_2](@organizationId) L ON L.LaneId = LCP.LaneID
	LEFT JOIN [dbo].[udtf_CurrentUsersInOrg_0_2](@organizationId) MIU ON MIU.UserId = LCP.StartUserId
	LEFT JOIN [dbo].[udtf_CurrentUsersInOrg_0_2](@organizationId) MOU ON MOU.UserId = LCP.EndUserId
	LEFT JOIN [dbo].[udtf_CurrentClassesOfServiceInOrg_0_2](@organizationId) [COS] ON [COS].[ClassOfServiceId] = [C].[ClassOfServiceId]
	JOIN [dbo].[udtf_CurrentCardTypesInOrg_0_2](@organizationId) [CT] ON [CT].[CardTypeId] = [C].[TypeId]
	JOIN [dbo].[udtf_CurrentBoardsInOrg_0_2](@organizationId) [B] ON [B].[BoardId] = [C].[BoardId]
WHERE LCP.IsApproximate = 0

)

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_SplitString]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE FUNCTION [dbo].[udtf_SplitString]
(
    @List       NVARCHAR(MAX),
    @Delimiter  NVARCHAR(10)
)
RETURNS TABLE
AS
    RETURN
    (
        SELECT DISTINCT
            [Value] = LTRIM(RTRIM(
                SUBSTRING(@List, [Number],
                CHARINDEX
                (
                  @Delimiter, @List + @Delimiter, [Number]
                ) - [Number])))
        FROM
            [dbo].[_Numbers]
        WHERE
            [Number] <= LEN(@List)
            AND SUBSTRING
            (
              @Delimiter + @List, [Number], LEN(@Delimiter)
            ) = @Delimiter
    );

GO
/****** Object:  UserDefinedFunction [dbo].[udtf_SplitString_0_2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE FUNCTION [dbo].[udtf_SplitString_0_2]
(
    @List       NVARCHAR(MAX),
    @Delimiter  NVARCHAR(10)
)
RETURNS TABLE
AS
    RETURN
    (
        SELECT DISTINCT
            [Value] = LTRIM(RTRIM(
                SUBSTRING(@List, [Number],
                CHARINDEX
                (
                  @Delimiter, @List + @Delimiter, [Number]
                ) - [Number])))
        FROM
            [dbo].[_Numbers]
        WHERE
            [Number] <= LEN(@List)
            AND SUBSTRING
            (
              @Delimiter + @List, [Number], LEN(@Delimiter)
            ) = @Delimiter
    );

GO
/****** Object:  View [dbo].[__MigrationLogCurrent]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

	CREATE VIEW [dbo].[__MigrationLogCurrent]
			AS
			WITH currentMigration AS
			(
			  SELECT 
				 migration_id, script_checksum, script_filename, complete_dt, applied_by, deployed, ROW_NUMBER() OVER(PARTITION BY migration_id ORDER BY sequence_no DESC) AS RowNumber
			  FROM [dbo].[__MigrationLog]
			)
			SELECT  migration_id, script_checksum, script_filename, complete_dt, applied_by, deployed
			FROM currentMigration
			WHERE RowNumber = 1
	
GO
ALTER TABLE [dbo].[__MigrationLog] ADD  CONSTRAINT [DF___MigrationLog_deployed]  DEFAULT ((1)) FOR [deployed]
GO
ALTER TABLE [dbo].[dim_Account] ADD  CONSTRAINT [DF__dim_Accou__IsApp__50FB042B]  DEFAULT ((0)) FOR [IsApproximate]
GO
ALTER TABLE [dbo].[dim_Board] ADD  CONSTRAINT [DF__dim_Board__IsApp__603D47BB]  DEFAULT ((0)) FOR [IsApproximate]
GO
ALTER TABLE [dbo].[dim_BoardRole] ADD  CONSTRAINT [DF__dim_BoardRole__IsAppr__5D60DB10]  DEFAULT ((0)) FOR [IsApproximate]
GO
ALTER TABLE [dbo].[dim_Card] ADD  CONSTRAINT [DF__dim_Card__IsAppr__5A846E65]  DEFAULT ((0)) FOR [IsApproximate]
GO
ALTER TABLE [dbo].[dim_Lane] ADD  CONSTRAINT [DF__dim_Lane__IsAppr__5D60DB10]  DEFAULT ((0)) FOR [IsApproximate]
GO
ALTER TABLE [dbo].[dim_Organization] ADD  CONSTRAINT [DF__dim_Organ__IsApp__4222D4EF]  DEFAULT ((0)) FOR [IsApproximate]
GO
ALTER TABLE [dbo].[dim_TaskBoards] ADD  CONSTRAINT [DF__dim_TaskB__IsApp__44FF419A]  DEFAULT ((0)) FOR [IsApproximate]
GO
ALTER TABLE [dbo].[dim_User] ADD  CONSTRAINT [DF__dim_User__IsAppr__4E1E9780]  DEFAULT ((0)) FOR [IsApproximate]
GO
ALTER TABLE [dbo].[fact_CardActualStartEndDateContainmentPeriod] ADD  CONSTRAINT [DF__fact_Card__IsApp__6ABAD62E]  DEFAULT ((0)) FOR [IsApproximate]
GO
ALTER TABLE [dbo].[fact_CardBlockContainmentPeriod] ADD  CONSTRAINT [DF__fact_Card__IsApp__13F1F5EB]  DEFAULT ((0)) FOR [IsApproximate]
GO
ALTER TABLE [dbo].[fact_CardLaneContainmentPeriod] ADD  CONSTRAINT [DF_fact_CardLaneContainmentPeriod_StartUserId]  DEFAULT ((0)) FOR [StartUserId]
GO
ALTER TABLE [dbo].[fact_CardLaneContainmentPeriod] ADD  CONSTRAINT [DF_fact_CardLaneContainmentPeriod_IsApproximate]  DEFAULT ((0)) FOR [IsApproximate]
GO
ALTER TABLE [dbo].[fact_CardsByOrganization] ADD  CONSTRAINT [DF__fact_Card__IsDel__1B9317B3]  DEFAULT ((0)) FOR [IsDeleted]
GO
ALTER TABLE [dbo].[fact_CardStartDueDateContainmentPeriod] ADD  CONSTRAINT [DF__fact_Card__IsApp__67DE6983]  DEFAULT ((0)) FOR [IsApproximate]
GO
ALTER TABLE [dbo].[fact_ReportExecution] ADD  CONSTRAINT [DF_fact_ReportExecution_ExecutionDate]  DEFAULT (getutcdate()) FOR [ExecutionDate]
GO
ALTER TABLE [dbo].[fact_UserAssignmentContainmentPeriod] ADD  CONSTRAINT [DF__fact_User__IsApp__11158940]  DEFAULT ((0)) FOR [IsApproximate]
GO
ALTER TABLE [dbo].[dim_CardTypes]  WITH CHECK ADD  CONSTRAINT [FK__dim_CardT__Entit__7A672E12] FOREIGN KEY([EntityExceptionId])
REFERENCES [dbo].[_EntityException] ([Id])
GO
ALTER TABLE [dbo].[dim_CardTypes] CHECK CONSTRAINT [FK__dim_CardT__Entit__7A672E12]
GO
ALTER TABLE [dbo].[dim_ClassOfService]  WITH CHECK ADD  CONSTRAINT [FK__dim_Class__Entit__7B5B524B] FOREIGN KEY([EntityExceptionId])
REFERENCES [dbo].[_EntityException] ([Id])
GO
ALTER TABLE [dbo].[dim_ClassOfService] CHECK CONSTRAINT [FK__dim_Class__Entit__7B5B524B]
GO
ALTER TABLE [dbo].[dim_Organization]  WITH CHECK ADD  CONSTRAINT [FK__dim_Organ__Entit__7C4F7684] FOREIGN KEY([EntityExceptionId])
REFERENCES [dbo].[_EntityException] ([Id])
GO
ALTER TABLE [dbo].[dim_Organization] CHECK CONSTRAINT [FK__dim_Organ__Entit__7C4F7684]
GO
/****** Object:  StoredProcedure [dbo].[sp_exceptions]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[sp_exceptions] (
	@boardId BIGINT,
	@userId BIGINT,
	@organizationId BIGINT,
	@hoursOffset INT = 0,
	@includedTagsString NVARCHAR(MAX) = '',
	@excludedTagsString NVARCHAR(MAX) = '',
	@includedCardTypesString NVARCHAR(MAX) = '',
	@includedClassesOfServiceString NVARCHAR(MAX) = ''
) AS

BEGIN

set nocount on;

declare @boardId2 bigint;
declare @organizationId2 bigint;

set @boardId2 = @boardId;
set @organizationId2 = @organizationId;

--select * from fnCustomReporting_Current_Cards_0_2(5);

declare @cardWork table
(
	DimRowId bigint not null,
	[Card ID] bigint not null INDEX idx_Col2 ([Card ID]),
	[Card Title] [nvarchar](256) NULL,
	[Description] [nvarchar](256) NULL,
	[Card Size] int null,
	[Is Card Blocked] bit null,
	[Current Blocked Reason] [nvarchar](256) NULL,
	[Creation Date] datetime null,
	[Planned Finish Date] datetime null,
	[Planned Start Date] datetime null,
	[Card Priority] nvarchar(16) null,
	[Current Lane Position] int null,
	[Card Link Name] [nvarchar](256) NULL,
	[Card Link Url] [nvarchar](256) NULL,
	[External Card ID] [nvarchar](256) NULL,
	[Tags] [nvarchar](256) NULL,
	[Current Lane ID] bigint null,
	[Current Lane Title] [nvarchar](256) NULL,
	[Current Full Lane Title] [nvarchar](256) NULL,
	[Current Board ID] bigint null,
	[Current Board Title] [nvarchar](256) NULL,
	[Custom Icon ID] bigint null,
	[Custom Icon Title] [nvarchar](256) NULL,
	[Card Type ID] bigint null,
	[Card Type Title] [nvarchar](256) NULL,
	[Connection Board ID] bigint null,
	[Parent Card ID] bigint null,
	[Last Moved Date] datetime null,
	[Attachments Count] int null,
	[Last Attachment Date] datetime null,
	[Comments Count] int null,
	[Last Comment Date] datetime null,
	[Last Activity Date] datetime null,
	[Archived Date] datetime null,
	[Last Actual Start Date] datetime null,
	[Last Actual Finish Date] datetime null,
	[Actual Duration (Days)] int null,
	[Actual Duration (Hours)] int null,
	[Actual Duration Minus Weekends (Days)] int null,
	[Planned Duration (Days)] int null,
	[Planned Duration (Hours)] int null,
	[Planned Duration Minus Weekends (Days)] int null,
	[Current Lane Type] varchar(16) null,
	[Current Lane Class]  varchar(16) null,

	[Block User ID] bigint null,
	[Block User Email] nvarchar(256) null,
	[Block Date] datetime null,

	[Org Host Name] nvarchar(256)
	 
	primary key(DimRowId)
);

--print '--- insert cardWork start - ' + CONVERT(varchar, SYSDATETIME(), 121);

insert into @cardWork
(
 DimRowId
 ,[Card ID]
 ,[Card Title]
 ,[Description]
 ,[Card Size]
 ,[Is Card Blocked]
 ,[Current Blocked Reason]
 ,[Creation Date]
 ,[Planned Finish Date]
 ,[Planned Start Date]
 ,[Card Priority]
 ,[Current Lane Position]
 ,[Card Link Name]
 ,[Card Link Url]
 ,[External Card ID]
 ,[Tags]
 ,[Current Lane ID]
 ,[Current Lane Title]
 ,[Current Full Lane Title]
 ,[Current Board ID]
 ,[Current Board Title]
 ,[Custom Icon ID]
 ,[Custom Icon Title]
 ,[Card Type ID]
 ,[Card Type Title]
 ,[Connection Board ID]
 ,[Parent Card ID]
 ,[Last Moved Date]
 ,[Attachments Count]
 ,[Last Attachment Date]
 ,[Comments Count]
 ,[Last Comment Date]
 ,[Last Activity Date]
 ,[Archived Date]
 ,[Last Actual Start Date]
 ,[Last Actual Finish Date]
 ,[Actual Duration (Days)]
 ,[Actual Duration (Hours)]
 ,[Actual Duration Minus Weekends (Days)]
 ,[Planned Duration (Days)]
 ,[Planned Duration (Hours)]
 ,[Planned Duration Minus Weekends (Days)]
 ,[Current Lane Type]
 ,[Current Lane Class]
)

	SELECT 
	[C].DimRowId
	   ,[C].[Id] AS [Card ID]
      ,LEFT(ISNULL([C].[Title],''), 255) AS [Card Title]
      ,LEFT(ISNULL([C].[Description],''), 255) AS [Description]
      ,[C].[Size] AS [Card Size]
      ,CONVERT(BIT, [C].[IsBlocked]) AS [Is Card Blocked]
      ,LEFT(ISNULL([C].[BlockReason],''), 255) AS [Current Blocked Reason]
      ,[C].[CreatedOn] AS [Creation Date]
      ,[C].[DueDate] AS [Planned Finish Date]
      ,[C].[StartDate] AS [Planned Start Date]
      , (CASE [C].[Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Card Priority]
      ,[C].[Index] AS [Current Lane Position]
      ,LEFT(ISNULL([C].[ExternalSystemName],''), 255) AS [Card Link Name]
      ,LEFT(ISNULL([C].[ExternalSystemUrl],''), 255) AS [Card Link Url]
      ,LEFT(ISNULL([C].[ExternalCardID],''), 255) AS [External Card ID]
      ,LEFT(ISNULL([C].[Tags],''), 255) AS [Tags]
      ,[C].[LaneId] AS [Current Lane ID]
      ,LEFT(ISNULL([L].[Title],''), 255) AS [Current Lane Title]
	  ,(CASE WHEN [L].[ParentLaneId] IS NULL THEN LEFT(ISNULL([L].[Title],''), 255) ELSE LEFT(ISNULL([PL].[Title] + ' -> ' + [L].[Title],''), 255)   END) AS [Current Full Lane Title]
	  ,[B].[Id] AS [Current Board ID]
      ,LEFT(ISNULL([B].[Title],''), 255) AS [Current Board Title]
      ,[C].[ClassOfServiceId] AS [Custom Icon ID]
      ,LEFT(ISNULL([COS].[TItle],''), 255) AS [Custom Icon Title]
	  ,[C].[TypeId] AS [Card Type ID]
	  ,[CardTypes].[Name] AS [Card Type Title]
	  ,[C].[DrillThroughBoardId] AS [Connection Board ID]
      ,[C].[ParentCardId] AS [Parent Card ID]
      ,[C].[LastMove] AS [Last Moved Date]
      ,[C].[AttachmentsCount] AS [Attachments Count]
      ,[C].[LastAttachment] AS [Last Attachment Date]
      ,[C].[CommentsCount] AS [Comments Count]
      ,[C].[LastComment] AS [Last Comment Date]
      ,[C].[LastActivity] AS [Last Activity Date]
      ,[C].[DateArchived] AS [Archived Date]
      ,DATEADD(HOUR, @hoursOffset, [C].[ActualStartDate]) AS [Last Actual Start Date]
      ,DATEADD(HOUR, @hoursOffset, [C].[ActualFinishDate]) AS [Last Actual Finish Date]
      ,DATEDIFF(DAY,DATEADD(HOUR, @hoursOffset, [C].[ActualStartDate]),DATEADD(HOUR, @hoursOffset, [C].[ActualFinishDate])) AS [Actual Duration (Days)]
      ,DATEDIFF(HOUR,DATEADD(HOUR, @hoursOffset, [C].[ActualStartDate]),DATEADD(HOUR, @hoursOffset, [C].[ActualFinishDate])) AS [Actual Duration (Hours)]
      ,DATEDIFF(DAY, DATEADD(HOUR, @hoursOffset, [C].[ActualStartDate]), DATEADD(HOUR, @hoursOffset, [C].[ActualFinishDate])) - (DATEDIFF(WEEK, DATEADD(HOUR, @hoursOffset, [C].[ActualStartDate]), DATEADD(HOUR, @hoursOffset, [C].[ActualFinishDate])) * 2) - 
			CASE WHEN DATEPART(dw,DATEADD(HOUR, @hoursOffset, [C].[ActualStartDate]) ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,DATEADD(HOUR, @hoursOffset, [C].[ActualFinishDate]) ) = 1 THEN 1 ELSE 0 END AS [Actual Duration Minus Weekends (Days)]
	  ,DATEDIFF(DAY,[C].[StartDate],[C].[DueDate]) AS [Planned Duration (Days)]
      ,DATEDIFF(HOUR,[C].[StartDate],[C].[DueDate]) AS [Planned Duration (Hours)]
      ,DATEDIFF(DAY, [C].[StartDate],[C].[DueDate]) - (DATEDIFF(WEEK, [StartDate],[DueDate]) * 2) - 
			CASE WHEN DATEPART(dw,[C].[StartDate] ) = 1 THEN 1 ELSE 0 END + CASE WHEN DATEPART(dw,[C].[DueDate] ) = 1 THEN 1 ELSE 0 END AS [Planned Duration Minus Weekends (Days)]
	   ,(CASE [L].[Type] WHEN 99 THEN 'Not Set' WHEN 1 THEN 'Ready' WHEN 2 THEN 'In Process' WHEN 3 THEN 'Completed' END) AS [Current Lane Type]
	   ,(CASE [L].[LaneTypeId] WHEN 0 THEN 'Backlog' WHEN 1 THEN 'OnBoard' WHEN 2 THEN 'Archive' END) AS [Current Lane Class]
  FROM 
	[dim_Board] [B]
	JOIN fnLib_GetBoardLanes(@boardId2) [L] ON [L].[BoardId] = [B].[Id]
	JOIN [dim_Card] [C] ON [C].[LaneId] = [L].[Id]
	JOIN [dbo].[udtf_CurrentCardTypes](@boardId2) [CardTypes]
		ON [CardTypes].[CardTypeId] = [C].[TypeId]
	JOIN [fnGetDefaultCardTypes](@boardId2, @includedCardTypesString) CT 
		ON CT.CardTypeId = [C].[TypeId] --Filter on Card Type

	LEFT JOIN [dbo].[udtf_CurrentClassesOfService](@boardId2) [COS]
		ON [COS].[ClassOfServiceId] = [C].[ClassOfServiceId]
	LEFT JOIN fnLib_GetBoardLanes(@boardId2) [PL] ON [PL].[Id] = [L].[ParentLaneId]
  WHERE [B].Id = @boardId2
	AND	[B].[OrganizationId] = @organizationId2
	AND [B].[ContainmentEndDate] IS NULL
	AND [B].[IsApproximate] = 0
	AND [B].[IsDeleted] = 0
	AND [L].[TaskBoardId] IS NULL
	AND [C].[ContainmentEndDate] IS NULL
	AND [C].[IsApproximate] = 0
	AND [C].[IsDeleted] = 0
	AND ISNULL([C].[ClassOfServiceId], 0) IN (SELECT ISNULL(ClassOfServiceId, 0) FROM  [fnGetDefaultClassesOfService](@boardId2, @includedClassesOfServiceString)) --Filter on Class of Service

--print '--- insert cardWork end - ' + CONVERT(varchar, SYSDATETIME(), 121);

 --weed out any dups due to mutiple open containments

 delete from @cardWork where DimRowId not in
 (select un.max_dimrow from
 (select max(DimRowId) as max_dimrow, [Card Id] from @cardWork group by [Card Id]) un);

 --print '--- weed dups end - ' + CONVERT(varchar, SYSDATETIME(), 121);

 	/* Region (Filter Include and Exclude Tags)  */
	BEGIN
		IF (NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL OR NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL)
		BEGIN
			-- Refresh the card tag cache
			EXECUTE [dbo].[usp_RefreshBoardCardCache] @boardId2, 1
		END

		--Filter on Included Tags
		IF NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL
		BEGIN
			DELETE FROM @cardWork
			WHERE [Card Id] NOT IN
			(SELECT [CardId] FROM [fnGetTagsList](@boardId2, @includedTagsString))
		END
		--Filter on Excluded Tags
		IF NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL
		BEGIN
			DELETE FROM @cardWork
			WHERE [Card Id] IN
			(SELECT [CardId] FROM [fnGetTagsList](@boardId2, @excludedTagsString))
		END
	END
	/* Region */


 -- add block user info

 declare @cardBlock table
 (
	DimRowId bigint,
	CardId bigint,
	BlockUserId bigint null,
	BlockEmail nvarchar(256) null,
	BlockDate datetime null
 );

 insert into @cardBlock
 (
	DimRowId,
	CardId,
	BlockUserId,
	BlockDate
) 
select
	cb.Id
	,cb.CardId
	,cb.StartUserId
	,cb.ContainmentStartDate
from @cardWork cw
 join fact_CardBlockContainmentPeriod cb on cw.[Card ID] = cb.CardID
 where cb.ContainmentEndDate is null and cb.IsApproximate = 0;

  --print '--- card block end - ' + CONVERT(varchar, SYSDATETIME(), 121);


 delete from @cardBlock where DimRowId not in
 (select un.max_dimrow from
 (select max(DimRowId) as max_dimrow, CardId from @cardBlock group by [CardId]) un);

   --print '--- card block dup weed end - ' + CONVERT(varchar, SYSDATETIME(), 121);

declare @user table
(
	Id bigint,
	EmailAddress nvarchar(256) null
);

insert into @user (Id, EmailAddress)
	select Id, EmailAddress from dim_user where DimRowId in
	(
		select du_unique.max_id from
		(
			select max(DimRowId) as max_id, Id from dim_user
			where ContainmentEndDate is null
			group by Id
		) du_unique
	);


   UPDATE cb SET cb.BlockEmail = du.EmailAddress FROM @cardBlock cb
   join @user du on cb.BlockUserId = du.Id;

   --print '--- email fetch end - ' + CONVERT(varchar, SYSDATETIME(), 121);


update cw set 
cw.[Block User ID] = cb.BlockUserId
,cw.[Block Date] = cb.BlockDate
,cw.[Block User Email] = cb.BlockEmail
from @cardWork cw
join @cardBlock cb on cw.[Card ID] = cb.CardId

   --print '--- update @cardWork with block info end - ' + CONVERT(varchar, SYSDATETIME(), 121);

declare @orgHostName nvarchar(256);
declare @orgDimRow bigint;

select @orgHostName = (select o.HostName from dim_Organization o join 
(select max(DimRowId) as DimRowId, Id from dim_Organization where Id = @organizationId2 group by Id) od on o.DimRowId = od.DimRowId);

SELECT 
 DimRowId
 ,[Card ID]
 ,[Card Title]
 ,[Description]
 ,[Card Size]
 ,[Is Card Blocked]
 ,[Current Blocked Reason]
 ,[Creation Date]
 ,[Planned Finish Date]
 ,[Planned Start Date]
 ,[Card Priority] AS [Priority]
 ,[Current Lane Position]
 ,[Card Link Name]
 ,[Card Link Url]
 ,[External Card ID]
 ,[Tags]
 ,[Current Lane ID]
 ,[Current Lane Title]
 ,[Current Full Lane Title]
 ,[Current Board ID]
 ,[Current Board Title]
 ,[Custom Icon ID]
 ,[Custom Icon Title]
 ,[Card Type ID]
 ,[Card Type Title]
 ,[Connection Board ID]
 ,[Parent Card ID]
 ,[Last Moved Date]
 ,[Attachments Count]
 ,[Last Attachment Date]
 ,[Comments Count]
 ,[Last Comment Date]
 ,[Last Activity Date]
 ,[Archived Date]
 ,[Last Actual Start Date]
 ,[Last Actual Finish Date]
 ,[Actual Duration (Days)]
 ,[Actual Duration (Hours)]
 ,[Actual Duration Minus Weekends (Days)]
 ,[Planned Duration (Days)]
 ,[Planned Duration (Hours)]
 ,[Planned Duration Minus Weekends (Days)]
 ,[Current Lane Type]
 ,[Current Lane Class]
 ,[Block User ID]
 ,[Block User Email]
 ,[Block Date]
 ,@orgHostName AS [Org Host Name]

 FROM @cardWork;

END




GO
/****** Object:  StoredProcedure [dbo].[sp_exceptions_v2]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



-- this is the redone proc

CREATE PROCEDURE [dbo].[sp_exceptions_v2] (
	@boardId BIGINT,
	@userId BIGINT,
	@organizationId BIGINT,
	@hoursOffset INT = 0,
	@includedTagsString NVARCHAR(MAX) = '',
	@excludedTagsString NVARCHAR(MAX) = '',
	@includedCardTypesString NVARCHAR(MAX) = '',
	@includedClassesOfServiceString NVARCHAR(MAX) = ''
) AS

BEGIN

set nocount on;

declare @boardId2 bigint;
declare @organizationId2 bigint;

set @boardId2 = @boardId;
set @organizationId2 = @organizationId;

--select * from fnCustomReporting_Current_Cards_0_2(5);

declare @cardWork table
(
	DimRowId bigint not null,
	[Card ID] bigint not null INDEX idx_Col2 ([Card ID]),
	[Card Title] [nvarchar](256) NULL,
	[Is Card Blocked] bit null,
	[Current Blocked Reason] [nvarchar](256) NULL,
	[Creation Date] datetime null,
	[Planned Finish Date] datetime null,
	[Planned Start Date] datetime null,
	[Card Priority] nvarchar(16) null,
	[External Card ID] [nvarchar](256) NULL,
	[Current Board ID] bigint null,
	[Current Board Title] [nvarchar](256) NULL,
	[Card Type ID] bigint null,
	[Card Type Title] [nvarchar](256) NULL,
	[Last Moved Date] datetime null,
	[Last Activity Date] datetime null,
	[Last Actual Start Date] datetime null,
	[Current Lane Class]  varchar(16) null,

	[Block User ID] bigint null, --  INDEX idx_lane_id NONCLUSTERED,
	[Block User Email] nvarchar(256) null,
	[Block Date] datetime null,

	[Org Host Name] nvarchar(256)
	 
	primary key(DimRowId)
);

--print '--- insert cardWork start -' + char(9) + CONVERT(varchar, SYSDATETIME(), 121);

insert into @cardWork
(
 DimRowId
 ,[Card ID]
 ,[Card Title]
 ,[Is Card Blocked]
 ,[Current Blocked Reason]
 ,[Creation Date]
 ,[Planned Finish Date]
 ,[Planned Start Date]
 ,[Card Priority]
 ,[External Card ID]
 ,[Current Board ID]
 ,[Current Board Title]
 ,[Card Type ID]
 ,[Card Type Title]
 ,[Last Moved Date]
 ,[Last Activity Date]
 ,[Last Actual Start Date]
 ,[Current Lane Class]
)

	SELECT 
	[C].DimRowId
	   ,[C].[Id] AS [Card ID]
      ,LEFT(ISNULL([C].[Title],''), 255) AS [Card Title]
      ,CONVERT(BIT, [C].[IsBlocked]) AS [Is Card Blocked]
      ,LEFT(ISNULL([C].[BlockReason],''), 255) AS [Current Blocked Reason]
      ,[C].[CreatedOn] AS [Creation Date]
      ,[C].[DueDate] AS [Planned Finish Date]
      ,[C].[StartDate] AS [Planned Start Date]
      , (CASE [C].[Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Card Priority]
      ,LEFT(ISNULL([C].[ExternalCardID],''), 255) AS [External Card ID]
	  ,[B].[Id] AS [Current Board ID]
      ,LEFT(ISNULL([B].[Title],''), 255) AS [Current Board Title]
	  ,[C].[TypeId] AS [Card Type ID]
	  ,[CardTypes].[Name] AS [Card Type Title]
      ,[C].[LastMove] AS [Last Moved Date]
      ,[C].[LastActivity] AS [Last Activity Date]
      ,DATEADD(HOUR, @hoursOffset, [C].[ActualStartDate]) AS [Last Actual Start Date]
	   ,(CASE [L].[LaneTypeId] WHEN 0 THEN 'OnBoard' WHEN 1 THEN 'Backlog' WHEN 2 THEN 'Archive' END) AS [Current Lane Class]
  FROM 
	[dim_Board] [B]
	JOIN fnLib_GetBoardLanes(@boardId2) [L] ON [L].[BoardId] = [B].[Id]
	JOIN [dim_Card] [C] ON [C].[LaneId] = [L].[Id]
	JOIN [dbo].[udtf_CurrentCardTypes](@boardId2) [CardTypes]
		ON [CardTypes].[CardTypeId] = [C].[TypeId]
	JOIN [fnGetDefaultCardTypes](@boardId2, @includedCardTypesString) CT 
		ON CT.CardTypeId = [C].[TypeId] --Filter on Card Type

	LEFT JOIN [dbo].[udtf_CurrentClassesOfService](@boardId2) [COS]
		ON [COS].[ClassOfServiceId] = [C].[ClassOfServiceId]
	LEFT JOIN fnLib_GetBoardLanes(@boardId2) [PL] ON [PL].[Id] = [L].[ParentLaneId]
  WHERE [B].Id = @boardId2
	AND	[B].[OrganizationId] = @organizationId2
	AND [B].[ContainmentEndDate] IS NULL
	AND [B].[IsApproximate] = 0
	AND [B].[IsDeleted] = 0
	AND [L].[TaskBoardId] IS NULL
	AND [C].[ContainmentEndDate] IS NULL
	AND [C].[IsApproximate] = 0
	AND [C].[IsDeleted] = 0
	AND ISNULL([C].[ClassOfServiceId], 0) IN (SELECT ISNULL(ClassOfServiceId, 0) FROM  [fnGetDefaultClassesOfService](@boardId2, @includedClassesOfServiceString)) --Filter on Class of Service

--print '--- insert cardWork end -' + char(9) + CONVERT(varchar, SYSDATETIME(), 121);

---- start of test code for dup inserts. the code below inserts dup records
---- for cards to test the dup weeing code

---- insert test dups for dup weeding code below to find
---- get a few card ID's to insert dups for. select ordered by CardTypeId to get
---- randomly positioned ones
--declare @testDupCardCount int;
--declare @testDupCardNdx int;
--set @testDupCardNdx = 1;

--declare @testDupCardDimRowIdStart int;
--set @testDupCardCount = 5;

--declare @testDupCardPeriodCount int;
--set @testDupCardPeriodCount = 3;

--declare @testDupCardIds table (Id int identity(1,1) not null, CardId bigint);
--insert into @testDupCardIds (CardId) select top (@testDupCardCount) [Card Id] from @cardWork order by [Card Type Id];
--While @testDupCardNdx <= @testDupCardCount
--Begin
--	declare @tempCardId bigint;
--	select @tempCardId = CardId from @testDupCardIds where Id = @testDupCardNdx

--	declare @testDupPeriodNdx int;
--	set @testDupPeriodNdx = 0;
--	while @testDupPeriodNdx < @testDupCardPeriodCount
--	begin
--		declare @testNewDimRowId int;
--		set @testNewDimRowId = (((@testDupCardNdx - 1) * @testDupCardPeriodCount) + @testDupPeriodNdx) + 100
--		insert into @cardWork
--		( DimRowId ,[Card ID]) select @testNewDimRowId, @tempCardId;

--		set @testDupPeriodNdx = @testDupPeriodNdx + 1;
--	end
--	set @testDupCardNdx = @testDupCardNdx + 1;
--End

-- end of test code for dup inserts


 --weed out any dups due to mutiple open containments
 declare @dupCards table
 (CardId bigint, DupCount int);

 declare @dupCardCount int;

 insert into @dupCards (CardId, DupCount)
select [Card ID], count(*) as DupCount from @cardWork group by [Card ID]
having count(*) > 1;

select @dupCardCount = count(*) from @dupCards;
--print '--- dup cards count=' + CAST(@dupCardCount as varchar(24));
if (@dupCardCount > 0)
begin
	delete @cardWork where DimRowId in
	(select remove_rows.DimRowId from
	(select cw.DimRowId, dc.CardId from @dupCards dc
	join @cardWork cw on dc.CardId = cw.[Card ID]
	except
	select max(cw.DimRowId), dc.CardId from @dupCards dc
	join @cardWork cw on dc.CardId = cw.[Card ID]
	group by dc.CardId) remove_rows);
end


 --print '--- weed dups end -' + char(9) + CONVERT(varchar, SYSDATETIME(), 121);

 	/* Region (Filter Include and Exclude Tags)  */
	BEGIN
		IF (NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL OR NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL)
		BEGIN
			-- Refresh the card tag cache
			EXECUTE [dbo].[usp_RefreshBoardCardCache] @boardId2, 1
		END

		--Filter on Included Tags
		IF NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL
		BEGIN
			DELETE FROM @cardWork
			WHERE [Card Id] NOT IN
			(SELECT [CardId] FROM [fnGetTagsList](@boardId2, @includedTagsString))
		END
		--Filter on Excluded Tags
		IF NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL
		BEGIN
			DELETE FROM @cardWork
			WHERE [Card Id] IN
			(SELECT [CardId] FROM [fnGetTagsList](@boardId2, @excludedTagsString))
		END
	END
	/* Region */


 -- add block user info

 declare @cardBlock table
 (
	DimRowId bigint,
	CardId bigint,
	BlockUserId bigint null,
	BlockEmail nvarchar(256) null,
	BlockDate datetime null
 );

 insert into @cardBlock
 (
	DimRowId,
	CardId,
	BlockUserId,
	BlockDate
) 
select
	cb.Id
	,cb.CardId
	,cb.StartUserId
	,cb.ContainmentStartDate
from @cardWork cw
 join fact_CardBlockContainmentPeriod cb on cw.[Card ID] = cb.CardID
 where cb.ContainmentEndDate is null and cb.IsApproximate = 0;

--print '--- card block end -' + char(9) + CONVERT(varchar, SYSDATETIME(), 121);


declare @user table
(
	Id bigint,
	EmailAddress nvarchar(256) null
);

insert into @user (Id, EmailAddress)
	select Id, EmailAddress from dim_user where 
	OrganizationId = @organizationId
	and ContainmentEndDate is null
	group by Id, EmailAddress;
	--and DimRowId in
	--(
	--	select du_unique.max_id from
	--	(
	--		select max(DimRowId) as max_id, Id from dim_user
	--		where ContainmentEndDate is null
	--		group by Id
	--	) du_unique
	--);


   UPDATE cb SET cb.BlockEmail = du.EmailAddress FROM @cardBlock cb
   join @user du on cb.BlockUserId = du.Id;

--print '--- email fetch end -' + char(9) + CONVERT(varchar, SYSDATETIME(), 121);


update cw set 
cw.[Block User ID] = cb.BlockUserId
,cw.[Block Date] = cb.BlockDate
,cw.[Block User Email] = cb.BlockEmail
from @cardWork cw
join @cardBlock cb on cw.[Card ID] = cb.CardId

--print '--- update @cardWork with block info end -' + char(9) + CONVERT(varchar, SYSDATETIME(), 121);

declare @orgHostName nvarchar(256);
declare @orgDimRow bigint;

select @orgHostName = (select o.HostName from dim_Organization o join 
(select max(DimRowId) as DimRowId, Id from dim_Organization where Id = @organizationId2 group by Id) od on o.DimRowId = od.DimRowId);

SELECT 
 DimRowId
 ,[Card ID]
 ,[Card Title]
 ,[Is Card Blocked]
 ,[Current Blocked Reason]
 ,[Creation Date]
 ,[Planned Finish Date]
 ,[Planned Start Date]
 ,[Card Priority] AS [Priority]
 ,[External Card ID]
 ,[Current Board ID]
 ,[Current Board Title]
 ,[Card Type ID]
 ,[Card Type Title]
 ,[Last Moved Date]
 ,[Last Activity Date]
 ,[Last Actual Start Date]
 ,[Current Lane Class]
 ,[Block User ID]
 ,[Block User Email]
 ,[Block Date]
 ,@orgHostName AS [Org Host Name]

 FROM @cardWork;

END





GO
/****** Object:  StoredProcedure [dbo].[sp_rework]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[sp_rework] (@boardId BIGINT,
	@includedCardTypesString NVARCHAR(MAX) = '',
	@includedClassesOfServiceString NVARCHAR(MAX) = ''
) AS

BEGIN

set nocount on;

declare @orgid bigint;
declare @dimBoardId bigint;

declare @containmentWork table
(
	Id bigint identity(1,1),
	[Card ID] bigint,
	[Card Title] nvarchar(255) null,
	[Card Size] int null,
	[Lane ID] bigint,
	[Lane Title] nvarchar(255) null,
	[Lane Class] nvarchar(24),
	[Lane Type] nvarchar(24),
	[Full Lane Title] nvarchar(2048),
	[Board ID] bigint,
	[Board Title] nvarchar(255) null,
	[Containment Start Date] datetime,
	[Containment End Date] datetime null,
	[Total Containment Duration (Days)] int,
	[Total Containment Duration (Hours)] int,
	[Total Containment Duration Minus Weekends (Days)] int,
	[MultipleContainmentsExist] int default(0),
	[CardIsRework] int default(0)

	primary key(Id)
);

set @dimBoardId = (select top 1 DimRowId from dim_Board where Id = @boardId and ContainmentEndDate is null order by DimRowId desc);
set @orgid = (select OrganizationId from dim_Board where DimRowId = @dimBoardId);

INSERT INTO @containmentWork
(
	[Card ID],
	[Card Title],
	[Card Size],
	[Lane ID] ,
	[Lane Title],
	[Lane Class],
	[Lane Type],
	[Full Lane Title],
	[Board ID],
	[Board Title],
	[Containment Start Date],
	[Containment End Date],
	[Total Containment Duration (Days)],
	[Total Containment Duration (Hours)],
	[Total Containment Duration Minus Weekends (Days)]
) SELECT
	[Card ID],
	[Card Title],
	[Card Size],
	[Lane ID] ,
	[Lane Title],
	[Lane Class],
	[Lane Type],
	[Full Lane Title],
	[Board ID],
	[Board Title],
	[Containment Start Date],
	[Containment End Date],
	[Total Containment Duration (Days)],
	[Total Containment Duration (Hours)],
	[Total Containment Duration Minus Weekends (Days)]

FROM [fnCustomReporting_CardLaneContainmentPeriods_0_2_byBoard](@orgId, @boardId)
JOIN [fnGetDefaultCardTypes_0_2](@boardId, @includedCardTypesString) CT ON CT.CardTypeId = [Card Type ID]
WHERE ISNULL([Custom Icon ID],0) IN (SELECT ISNULL(ClassOfServiceId,0) FROM  [fnGetDefaultClassesOfService_0_2](@boardId, @includedClassesOfServiceString))


DECLARE @multipleContainments TABLE
(
	[Card ID] BIGINT,
	[Lane ID] BIGINT
);

INSERT INTO @multipleContainments
SELECT [Card Id], [Lane Id] FROM @containmentWork GROUP BY [Card Id], [Lane Id]
HAVING COUNT(*) > 1;

UPDATE cw SET cw.[MultipleContainmentsExist] = 1 FROM @containmentWork cw
JOIN (SELECT MAX(id) AS [Last ID], cw.[Card ID], cw.[Lane ID] FROM @containmentWork cw 
	JOIN @multipleContainments mc ON cw.[Card ID] = mc.[Card ID] AND cw.[Lane ID] = mc.[Lane ID]
	GROUP BY cw.[Card ID], cw.[Lane ID]) mc ON cw.Id = mc.[Last ID]

UPDATE cw SET cw.[CardIsRework] = 1 FROM @containmentWork cw
JOIN @multipleContainments mc ON cw.[Card ID] = mc.[Card ID] AND cw.[Lane ID] = mc.[Lane ID];

SELECT 	[Card ID],
	[Card Title],
	[Card Size],
	[Lane ID] ,
	[Lane Title],
	[Lane Class],
	[Lane Type],
	[Full Lane Title],
	[Board ID],
	[Board Title],
	[Containment Start Date],
	[Containment End Date],
	[Total Containment Duration (Days)],
	[Total Containment Duration (Hours)],
	[Total Containment Duration Minus Weekends (Days)],
	[MultipleContainmentsExist],
	[CardIsRework]
 FROM @containmentWork;

--select
--	[Card ID] as [CardID]

--from [fnCustomReporting_CardLaneContainmentPeriods_0_2](5);

END


GO
/****** Object:  StoredProcedure [dbo].[spBurnDown]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[spBurnDown] (

	@boardId BIGINT,
	@userId BIGINT,
	@startDate DATETIME = NULL,
	@endDate DATETIME = NULL,
	@startLanesString NVARCHAR(MAX) = '',
	@finishLanesString NVARCHAR(MAX) = '',
	--@finishLaneId BIGINT = NULL,
 	--@rollupLanesString NVARCHAR(MAX) = '',
	--@excludedLanesString NVARCHAR(MAX) = '',
	@includedTagsString NVARCHAR(MAX) = '',
	@excludedTagsString NVARCHAR(MAX) = '',
	@includedCardTypesString NVARCHAR(MAX) = '',
	@includedClassesOfServiceString NVARCHAR(MAX) = '',
	@hoursOffset INT = 0,
	@organizationId BIGINT
)

AS

BEGIN

SET NOCOUNT ON;

INSERT INTO [dbo].[fact_ReportExecution] ([ReportName], [OrgId], [UserId], [BoardId], [ExecutionDate])
VALUES ('Burndown', @organizationId, @userId, @boardId, GETUTCDATE())

DECLARE

@minDate DATETIME,
@maxDate DATETIME,
@endDateOrdinal BIGINT,
@useIncludeTagTable BIT,
@useExcludeTagTable BIT


	DECLARE @BurnDownRecords TABLE (
			[MeasureDate] DATETIME,
			--[CardId] INT,
			--[CardTitle] NVARCHAR(255),
			[CardCount] BIGINT,
			[CardSize] BIGINT,
			[MinCardCount] BIGINT,
			[MinCardSize] BIGINT,
			[Planned_Type] VARCHAR(9)
		)


IF @organizationId <> (SELECT [OrganizationId] FROM [udtf_CurrentBoards_0_2](@boardId))
BEGIN
	SELECT * FROM @BurnDownRecords
	RETURN
END


--Assert user has access to the board, else return empty data
IF (SELECT [dbo].[fnGetUserBoardRole_0_2](@boardId, @userId)) = 0
BEGIN
	SELECT * FROM @BurnDownRecords
	RETURN
END

BEGIN /* Region (Min and Max Date Calculations) */

	IF (@startDate IS NULL)
		BEGIN
			SELECT @minDate = [dbo].[fnGetMinimumDate_0_2](@boardId,@hoursOffset)
		END 
		ELSE 
		BEGIN 
			SELECT @minDate = @startDate
		END

		IF (@endDate IS NULL)
		BEGIN
			SELECT @endDateOrdinal = ((CAST(dt.[Id] AS BIGINT) * 100000) + (3600 * @hoursOffset))
				, @maxDate = DATEADD(HOUR, @hoursOffset, dt.[Date])
			FROM [dim_Date] dt
			WHERE dt.[Date] = CONVERT(DATETIME, DATEDIFF(DAY, 0, GETUTCDATE()))
		END 
		ELSE 
		BEGIN
			SELECT @endDateOrdinal = ((CAST(dt.[Id] AS BIGINT) * 100000) + (3600 * @hoursOffset))
				, @maxDate = DATEADD(HOUR, @hoursOffset, dt.[Date])
			FROM [dim_Date] dt
			WHERE dt.[Date] = @endDate 
	END

END /* Region */


BEGIN /* Region (Include and Exclude Tags)  */
		SELECT @useIncludeTagTable = 0, @useExcludeTagTable = 0

		

		DECLARE @cardWithIncludeTags TABLE
		(
			CardId BIGINT
		)

		DECLARE @cardWithExcludeTags TABLE
		(
			CardId BIGINT
		)


		IF (NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL OR NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL)
		BEGIN
			-- Refresh the card tag cache
			EXECUTE [dbo].[usp_RefreshBoardCardCache] @boardId, 1
		END

		IF NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL
		BEGIN
			SET @useIncludeTagTable = 1

			INSERT INTO @cardWithIncludeTags
			SELECT [CardId]
			FROM [fnGetTagsList_0_2](@boardId, @includedTagsString)
		END

		IF NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL
		BEGIN
			SET @useExcludeTagTable = 1

			INSERT INTO @cardWithExcludeTags
			SELECT [CardId]
			FROM [fnGetTagsList_0_2](@boardId, @excludedTagsString)

			--PRINT 'Using Exclude Tags'
		END
END /* Region */


BEGIN /* Region (Date Filtering)  */
DECLARE @dateTable TABLE (
	[Date] DATETIME
	, DateCompareOrdinal BIGINT
)

--Insert the dates and the corresponding ordinals into a TABLE
INSERT INTO @dateTable
SELECT  DT.[Date]
		, ((CAST(dt.[Id] AS BIGINT) * 100000) + (3600 * @hoursOffset))
FROM [dim_Date] DT
WHERE DT.[Date] BETWEEN @minDate AND @maxDate
		
END /* Region */


BEGIN /* Region (Card Filtering)  */
		
DECLARE @filteredCardsPlanned TABLE (
	Id BIGINT,
	Title NVARCHAR(255),
	Size INT
)
INSERT INTO @filteredCardsPlanned
SELECT DISTINCT
CC.CardId, 
CC.Title,
CC.Size
FROM [dbo].fact_CardLaneContainmentPeriod CP
JOIN [dbo].[udtf_CurrentCards_0_2] (@boardId) CC ON CC.CardId=CP.CardID
INNER JOIN [dbo].[fnGetStartLanes_0_2] (@boardId,@startLanesString) SL ON SL.LaneId = CP.LaneID
JOIN [dbo].[udtf_CurrentLanes_0_2](@boardId) L ON CP.LaneId = L.LaneId
LEFT JOIN @cardWithIncludeTags IT ON IT.CardId = CP.CardId
LEFT JOIN @cardWithExcludeTags ET ON ET.CardId = CP.CardId
JOIN [fnGetDefaultCardTypes_0_2](@boardId, @includedCardTypesString) CT ON CT.CardTypeId = CC.TypeID
WHERE L.BoardId = @boardId
AND CP.ContainmentStartDate BETWEEN @startDate AND DATEADD(ss,-1,DATEADD(hh,24,@startDate))
	--AND CP.ContainmentStartDate BETWEEN @startDate and dateadd(hh,24,@startDate) 
	AND CP.CardId = (CASE WHEN @useIncludeTagTable = 1 THEN IT.CardId ELSE CP.CardId END)
	AND ((@useExcludeTagTable = 1 AND ET.CardId IS NULL) OR @useExcludeTagTable = 0)
	AND ISNULL(CC.ClassOfServiceId,0) IN (SELECT ISNULL(ClassOfServiceId,0) FROM  [fnGetDefaultClassesOfService_0_2](@boardId, @includedClassesOfServiceString))


END /* Region */			



BEGIN /* Region (Card Filtering)  */
		
DECLARE @filteredCardsUnplanned TABLE (
	Id BIGINT,
	Title NVARCHAR(255),
	Size INT
)
INSERT INTO @filteredCardsUnPlanned
SELECT DISTINCT
CC.CardId, 
CC.Title,
CC.Size
FROM [dbo].fact_CardLaneContainmentPeriod CP
JOIN [dbo].[udtf_CurrentCards_0_2] (@boardId) CC ON CC.CardId=CP.CardID
INNER JOIN [dbo].[fnGetStartLanes_0_2] (@boardId,@startLanesString) SL ON SL.LaneId = CP.LaneID
JOIN [dbo].[udtf_CurrentLanes_0_2](@boardId) L ON CP.LaneId = L.LaneId
LEFT JOIN @cardWithIncludeTags IT ON IT.CardId = CP.CardId
LEFT JOIN @cardWithExcludeTags ET ON ET.CardId = CP.CardId
JOIN [fnGetDefaultCardTypes_0_2](@boardId, @includedCardTypesString) CT ON CT.CardTypeId = CC.TypeID
WHERE L.BoardId = @boardId
AND CP.ContainmentStartDate BETWEEN DATEADD(hh,24,@startDate) AND @endDate
AND CC.CardId NOT IN (SELECT FCP.Id FROM @filteredCardsPlanned FCP)  
AND CP.CardId = (CASE WHEN @useIncludeTagTable = 1 THEN IT.CardId ELSE CP.CardId END)
AND ((@useExcludeTagTable = 1 AND ET.CardId IS NULL) OR @useExcludeTagTable = 0)
AND ISNULL(CC.ClassOfServiceId,0) IN (SELECT ISNULL(ClassOfServiceId,0) FROM  [fnGetDefaultClassesOfService_0_2](@boardId, @includedClassesOfServiceString))


END /* Region */	



BEGIN


/* Region (Planned Cards) */		
INSERT INTO @BurnDownRecords
SELECT DISTINCT
	--CP.LaneId AS LaneId
	--, L.Title AS LaneTitle
	--, L.LaneTypeId AS LaneTypeId
	DT.[Date] AS MeasureDate
	,C.Id AS CardCount
	--,C.Title
	--,CP.ContainmentStartDate
	--,CP.ContainmentEndDate
	--, COUNT(DISTINCT C.Id) AS CardCount
	, CASE WHEN MAX(C.Size) IS NULL OR MAX(C.Size) = 0 THEN 1 ELSE MAX(C.Size) END as CardSize
	--, [LaneRank] AS OrderBy
	, 0 AS MinCardCount
	, 0 AS MinCardSize
	, 'Planned' AS Planned_Type
FROM [fact_CardLaneContainmentPeriod] CP
JOIN @dateTable DT ON DT.Date 
 BETWEEN CAST(CP.ContainmentStartDate AS DATE) AND CAST(ISNULL(CP.ContainmentEndDate, GETUTCDATE()) AS DATE)
JOIN @filteredCardsPlanned C ON CP.CardID = C.Id
FULL OUTER JOIN [dbo].[fnGetFinishLanes_0_2](@boardId,@finishLanesString) FL ON FL.LaneID=CP.LaneID
JOIN [dbo].[udtf_CurrentLanes_0_2](@boardId) L ON CP.LaneId = L.LaneId
WHERE FL.LaneID is null
--LEFT JOIN @childToParentMappingForRollup RL ON RL.ChildLaneId = CP.LaneID
--JOIN [fnGetLaneOrder_0_2](@boardId) O ON O.LaneID = ISNULL(RL.RollupLaneId, CP.LaneID)
GROUP BY --ISNULL(RL.RollupLaneId, CP.LaneId)
	--,  ISNULL(RL.RollupLaneTitle, L.Title)
	--CP.LaneID
	--,L.Title
	--, L.LaneTypeId 
	C.Id
	--,C.Title
	--,CP.ContainmentStartDate
	--,CP.ContainmentEndDate
	 ,DT.[Date]
	--, O.[LaneRank]

--HAVING  ISNULL(RL.RollupLaneId, CP.LaneId) NOT IN (SELECT [ChildLaneId] 
--											FROM @childToParentMappingForRollup)
END



BEGIN
INSERT INTO @BurnDownRecords

SELECT DISTINCT
	--CP.LaneId AS LaneId
	--, L.Title AS LaneTitle
	--, L.LaneTypeId AS LaneTypeId
	DT.[Date] AS MeasureDate
	,C.Id AS CardCount
	--,C.Title
	--,CP.ContainmentStartDate
	--,CP.ContainmentEndDate
	--, COUNT(DISTINCT C.Id) AS CardCount
	, CASE WHEN MAX(C.Size) IS NULL OR MAX(C.Size) = 0 THEN 1 ELSE MAX(C.Size) END as CardSize
	--, [LaneRank] AS OrderBy
	, 0 AS MinCardCount
	, 0 AS MinCardSize
	, 'Unplanned' AS Planned_Type
FROM [fact_CardLaneContainmentPeriod] CP
JOIN @dateTable DT ON DT.Date 
	BETWEEN CAST(CP.ContainmentStartDate AS DATE) AND CAST(ISNULL(CP.ContainmentEndDate, GETUTCDATE()) AS DATE)
FULL OUTER JOIN [dbo].[fnGetFinishLanes_0_2](@boardId,@finishLanesString) FL ON FL.LaneID=CP.LaneID
JOIN @filteredCardsUnplanned C ON CP.CardID = C.Id
JOIN [dbo].[udtf_CurrentLanes_0_2](@boardId) L ON CP.LaneId = L.LaneId
--LEFT JOIN @childToParentMappingForRollup RL ON RL.ChildLaneId = CP.LaneID
WHERE FL.LaneID is null
AND CP.ContainmentStartDate BETWEEN dateadd(hh,24, @minDate) and @maxDate 
GROUP BY --ISNULL(RL.RollupLaneId, CP.LaneId)
	--,  ISNULL(RL.RollupLaneTitle, L.Title)
	--CP.LaneID
	--,L.Title
	--,L.LaneTypeId 
	C.Id
	--,C.Title
	--,CP.ContainmentStartDate
	--,CP.ContainmentEndDate
	,DT.[Date]
	--, O.[LaneRank]

--HAVING  ISNULL(RL.RollupLaneId, CP.LaneId) NOT IN (SELECT [ChildLaneId] 
--											FROM @childToParentMappingForRollup)

END

BEGIN /* Region (Select the resultset with filler PLANNED) */
	INSERT INTO @BurnDownRecords
	 SELECT DT.[Date] AS MeasureDate
		, NULL AS CardCount
		, 0 AS CardSize
		--, [LaneRank] AS OrderBy
		, 0 AS MinCardCount
		, 0 AS MinCardSize
		, 'Planned' AS Planned_Type
		FROM @dateTable DT
		WHERE DT.[Date] BETWEEN @minDate AND @maxDate

END /* Region  */


BEGIN /* Region (Select the resultset with filler UNPLANNED) */
	INSERT INTO @BurnDownRecords
	 SELECT DT.[Date] AS MeasureDate
		, NULL AS CardCount
		, 0 AS CardSize
		--, [LaneRank] AS OrderBy
		, 0 AS MinCardCount
		, 0 AS MinCardSize
		, 'Unplanned' AS Planned_Type
		FROM @dateTable DT
		WHERE DT.[Date] BETWEEN @minDate AND @maxDate

END /* Region  */



SELECT DISTINCT 
	BDR.MeasureDate
	,COUNT(DISTINCT BDR.CardCount) AS CardCount
	,SUM(BDR.CardSize) AS CardSize
	,SUM(BDR.MinCardCount) AS MinCardCount
	,SUM(BDR.MinCardSize) AS MinCardSize
	,BDR.Planned_Type
FROM @BurnDownRecords BDR
GROUP BY BDR.MeasureDate
 ,BDR.Planned_Type
ORDER BY MeasureDate

END





GO
/****** Object:  StoredProcedure [dbo].[spBurnupChart]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[spBurnupChart] 
	@boardId BIGINT, 
	@userId BIGINT,
	@startLaneId BIGINT = NULL,
	@finishLaneId BIGINT = NULL,
	@numberOfDaysBack INT = 30, 
	@numberOfDaysForward INT = 30,
	@excludedLanesString NVARCHAR(MAX) = '',
	@includedTagsString NVARCHAR(MAX) = '',
	@excludedTagsString NVARCHAR(MAX) = '',
	@includedCardTypesString NVARCHAR(MAX) = '',
	@includedClassesOfServiceString NVARCHAR(MAX) = '',
	@offsetHours INT = 0,
	@organizationId BIGINT
AS
BEGIN
	-- SET NOCOUNT ON added to prevent extra result sets from
	-- interfering with SELECT statements.
	SET NOCOUNT ON;

	INSERT INTO [dbo].[fact_ReportExecution] ([ReportName], [OrgId], [UserId], [BoardId], [ExecutionDate])
	VALUES ('Burnup', @organizationId, @userId, @boardId, GETUTCDATE())

	DECLARE @trendRows TABLE (
	TrendName NVARCHAR(50),
	MeasurementDate DATETIME,
	CardCountOnDate DECIMAL(19,10),
	CardSizeOnDate DECIMAL(19,10),
	DailyCountTrend DECIMAL(19,10),
	DailySizeTrend DECIMAL(19,10)
	)

	IF @organizationId <> (SELECT [OrgId] FROM [dbo].[udtf_CurrentBoards](@boardId))
	BEGIN
		SELECT * FROM @trendRows
		RETURN
	END

	--Assert user has access to the board, else return empty data
	IF (SELECT [dbo].[fnGetUserBoardRole](@boardId, @userId)) = 0
	BEGIN
		SELECT * FROM @trendRows
		RETURN
	END

	--Get the startLaneId and finishLaneId if not specified
	SET @startLaneId = [dbo].[fnDetermineBurnupStartLane](@boardId,@startLaneId)
	SET @finishLaneId = [dbo].[fnDetermineBurnupFinishLane](@boardId,@finishLaneId)

	DECLARE @overallTragectoryName NVARCHAR(50),@currentBurnupTrajectoryName NVARCHAR(50), @idealTrajectoryName NVARCHAR(50),@requiredTrajectoryName NVARCHAR(50)
	SELECT @overallTragectoryName = 'Starting new work'
		  ,@currentBurnupTrajectoryName = 'Finishing work in process'
		  ,@idealTrajectoryName = 'Should have been'
		  ,@requiredTrajectoryName = 'Needed from today to hit target date'

	DECLARE @startOfTrajectoryDate DATETIME
	DECLARE @endOfTrajectoryDate DATETIME
	DECLARE @currentTrajectoryDate DATETIME
	DECLARE @startCount DECIMAL(19,10)
	DECLARE @startSize DECIMAL(19,10)
	DECLARE @endCount DECIMAL(19,10)
	DECLARE @endSize DECIMAL(19,10)

	IF (NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL OR NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL)
	BEGIN
		-- Refresh the card tag cache
		EXECUTE [dbo].[usp_RefreshBoardCardCache] @boardId, 1
	END

	INSERT INTO @trendRows
    SELECT *
	FROM [fnGetBurnupTrendLineForLane] (@boardId,@startLaneId,@numberOfDaysBack,@numberOfDaysForward, @overallTragectoryName,@excludedLanesString,@includedTagsString,@excludedTagsString,@includedCardTypesString,@includedClassesOfServiceString,@offsetHours)
	UNION ALL
	SELECT *
	FROM [fnGetBurnupTrendLineForLane] (@boardId,@finishLaneId,@numberOfDaysBack,@numberOfDaysForward, @currentBurnupTrajectoryName,@excludedLanesString,@includedTagsString,@excludedTagsString,@includedCardTypesString,@includedClassesOfServiceString,@offsetHours)

	--Get the Ideal trajectory line parameters
	SELECT @startOfTrajectoryDate = CONVERT(DATE,DATEADD(DAY,-@numberOfDaysBack,DATEADD(HOUR,@offsetHours,GETUTCDATE())))
		  ,@endOfTrajectoryDate = CONVERT(DATE,DATEADD(DAY,@numberOfDaysForward,DATEADD(HOUR,@offsetHours,GETUTCDATE())))
		  ,@currentTrajectoryDate = CONVERT(DATE,DATEADD(HOUR,@offsetHours,GETUTCDATE()))

	SELECT @startCount = CardCountOnDate, @startSize = CardSizeOnDate
	FROM @trendRows
	WHERE TrendName = @currentBurnupTrajectoryName
		  AND MeasurementDate = @startOfTrajectoryDate

	SELECT @endCount = CardCountOnDate, @endSize = CardSizeOnDate
	FROM @trendRows
	WHERE TrendName = @overallTragectoryName
		  AND MeasurementDate = @currentTrajectoryDate
	
	INSERT INTO @trendRows
	SELECT *
	FROM dbo.fnGetCalculatedBurnupTrajectory(@startCount,@startSize,@endCount,@endSize,@startOfTrajectoryDate,@endOfTrajectoryDate,@idealTrajectoryName)


	--Get the Required trajecotry parameters
	SELECT @startCount = CardCountOnDate, @startSize = CardSizeOnDate
	FROM @trendRows
	WHERE TrendName = @currentBurnupTrajectoryName
		  AND MeasurementDate = @currentTrajectoryDate

	SELECT @endCount = CardCountOnDate, @endSize = CardSizeOnDate
	FROM @trendRows
	WHERE TrendName = @overallTragectoryName
		  AND MeasurementDate = @currentTrajectoryDate
	
	INSERT INTO @trendRows
	SELECT *
	FROM dbo.fnGetCalculatedBurnupTrajectory(@startCount,@startSize,@endCount,@endSize,@currentTrajectoryDate,@endOfTrajectoryDate,@requiredTrajectoryName)
	IF (SELECT SUM(CardCountOnDate) FROM @trendRows ) = 0 DELETE FROM @trendrows
	 
	SELECT * FROM @trendRows
END







GO
/****** Object:  StoredProcedure [dbo].[spCardDistribution]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO
CREATE PROCEDURE [dbo].[spCardDistribution]
	@boardId BIGINT,
	@userId BIGINT,
	@rollupLanesString NVARCHAR(MAX) = '',
	@excludedLanesString NVARCHAR(MAX) = '',
	@includedTagsString NVARCHAR(MAX) = '',
	@excludedTagsString NVARCHAR(MAX) = '',
	@includedCardTypesString NVARCHAR(MAX) = '',
	@includedClassesOfServiceString NVARCHAR(MAX) = '',
	@organizationId BIGINT
AS
BEGIN
	SET NOCOUNT ON;

	INSERT INTO [dbo].[fact_ReportExecution] ([ReportName], [OrgId], [UserId], [BoardId], [ExecutionDate])
	VALUES ('Card Distribution', @organizationId, @userId, @boardId, GETUTCDATE())

	DECLARE @returnTable TABLE
		(
			[Card Id] BIGINT NOT NULL,
			[Type] NVARCHAR(64) NOT NULL,
			[Priority] VARCHAR(8) NOT NULL,
			[Class of Service] NVARCHAR(255) NOT NULL,
			[Size] INT NOT NULL,
			[Lane Title] NVARCHAR(255) NOT NULL,
			[Parent Lane Title] NVARCHAR(255) NULL,
			[Lane Id] BIGINT NOT NULL
		)

	--Asserts organization has access to the board, else return empty data
	IF @organizationId <> (SELECT [OrgId] FROM [udtf_CurrentBoards](@boardId))
	BEGIN
		SELECT * FROM @returnTable
		RETURN
	END

	--Assert user has access to the board, else return empty data
	IF (SELECT [dbo].[fnGetUserBoardRole](@boardId, @userId)) = 0
	BEGIN
		SELECT * FROM @returnTable
		RETURN
	END

	DECLARE @useIncludeTagTable BIT
	DECLARE @useExcludeTagTable BIT

	DECLARE @orgLanes TABLE
	(
		[LaneId] BIGINT,
		[LaneTitle] NVARCHAR(255),
		[ParentLaneId] BIGINT,
		[ParentLaneTitle] NVARCHAR(255)
	)

	INSERT INTO @orgLanes
	([LaneId], [LaneTitle], [ParentLaneId])
	SELECT
		LaneId,
		Title,
		ParentLaneId
	FROM
	[dbo].[udtf_CurrentLanes](@boardId)

	UPDATE @orgLanes
	SET ParentLaneTitle = [L].LaneTitle
	FROM @orgLanes [L]
	WHERE [L].LaneId = ParentLaneId

	/* Region (Get Card Data)  */
	BEGIN
		INSERT INTO @returnTable
		SELECT
		DISTINCT [Card].[CardId] as [Card Id],
		[CardTypes].[Name],
		(CASE [Card].[Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Priority],
		(CASE WHEN [ClassOfService].[Title] IS NULL THEN 'Not Set' ELSE [ClassOfService].[Title] END) as [Class of Service],
		(CASE WHEN ([Card].[Size] = 0 OR [Card].[Size] IS NULL) THEN 1 ELSE [Card].[Size] END) AS [Size],
		[Lane].[LaneTitle] as [Lane Title],
		[ParentLane].[Title] as [Parent Lane Title],
		[Lane].[LaneId] as [Lane Id]
		FROM [dbo].[udtf_CurrentCards_0_3](@boardId) as [Card]

				--this join eliminates dup poen containments
				join	
               (select max(ContainmentStartDate) as maxdim, [CardId] from 
                [dbo].[udtf_CurrentCards_0_3](@boardId)
                group by [CardId]) dup on [Card].ContainmentStartDate = dup.maxdim
				and 
				[Card].CardId = dup.CardId

		JOIN [dbo].[udtf_CurrentCardTypes](@boardId) [CardTypes]
		ON [CardTypes].[CardTypeId] = [Card].[TypeId]
		LEFT JOIN [dbo].[udtf_CurrentClassesOfService](@boardId) [ClassOfService]
		ON [ClassOfService].[ClassOfServiceId] = [Card].[ClassOfServiceId]
		JOIN @orgLanes as [Lane]
		ON [Lane].[LaneId] = [Card].[LaneId]
		LEFT JOIN [dbo].[udtf_CurrentLanes](@boardId) as [ParentLane]
		ON [Lane].[ParentLaneId] = [ParentLane].[LaneId]
		JOIN [fnGetDefaultCardTypes](@boardId, @includedCardTypesString) CT 
		ON CT.CardTypeId = [Card].[TypeId] --Filter on Card Type
		WHERE [Lane].[LaneId] NOT IN (SELECT * FROM [fnSplitLaneParameterString](@excludedLanesString)) --Filter lanes from @excludedLanesString
		AND ISNULL([Card].[ClassOfServiceId], 0) IN (SELECT ISNULL(ClassOfServiceId, 0) FROM  [fnGetDefaultClassesOfService](@boardId, @includedClassesOfServiceString)) --Filter on Class of Service
	END
	/* Region */

	/* Region (Filter Include and Exclude Tags)  */
	BEGIN
		IF (NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL OR NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL)
		BEGIN
			-- Refresh the card tag cache
			EXECUTE [dbo].[usp_RefreshBoardCardCache] @boardId, 1
		END

		--Filter on Included Tags
		IF NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL
		BEGIN
			DELETE FROM @returnTable
			WHERE [Card Id] NOT IN
			(SELECT [CardId] FROM [fnGetTagsList](@boardId, @includedTagsString))
		END
		--Filter on Excluded Tags
		IF NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL
		BEGIN
			DELETE FROM @returnTable
			WHERE [Card Id] IN
			(SELECT [CardId] FROM [fnGetTagsList](@boardId, @excludedTagsString))
		END
	END
	/* Region */

	/* Region (Child Lane Rollups)  */
	BEGIN
		DECLARE @childToParentMappingForRollup TABLE
		(
			ChildLaneId BIGINT,
			RollupLaneId BIGINT,
			RollupLaneTitle NVARCHAR(255),
			RollupLaneTypeId INT,
			RollupParentLaneId BIGINT
			PRIMARY KEY (ChildLaneId, RollupLaneId)
		)

		INSERT INTO @childToParentMappingForRollup
		SELECT sub.[LaneId] AS [ChildLaneId], glo.[LaneId] AS [RollupLaneId], glo.[LaneTitle] AS [RollupLaneTitle], glo.[LaneTypeId] AS [RollupLaneTypeId], glo.ParentLaneId AS [RollupParentLaneId]--, glo.[PathString]--, sub.[LaneId], sub.[LaneTitle], sub.[PathString]
		FROM [dbo].[fnGetLaneOrder](@boardId) glo
		INNER JOIN [fnSplitLaneParameterString](@rollupLanesString) slps
			ON glo.[LaneId] = slps.[LaneId]
		INNER JOIN (
			SELECT b.[LaneId], b.[LaneTitle], b.[PathString] FROM [dbo].[fnGetLaneOrder](@boardId) b
		) sub
			ON sub.[PathString] LIKE glo.[PathString] + '%' AND LEN(sub.[PathString]) <> LEN(glo.[PathString])

		IF EXISTS (SELECT TOP 1 [ChildLaneId] FROM @childToParentMappingForRollup)
		BEGIN
			--PRINT 'Updating return table'
			--Rename child lanes to their parent, set child lane id to parent lane id
			UPDATE rt
			SET rt.[Lane Id] = ru.[RollupLaneId]
			, rt.[Lane Title] = ru.[RollupLaneTitle]
			, rt.[Parent Lane Title] = PL.LaneTitle
			FROM @returnTable AS rt
			INNER JOIN @childToParentMappingForRollup ru
				ON rt.[Lane Id] = ru.[ChildLaneId]
			LEFT JOIN @orgLanes PL
				ON PL.LaneId = ru.RollupParentLaneId
		END
	END
	/* Region */

	/* Region (Return Data) */
	SELECT * FROM @returnTable
	/* Region */
END


GO
/****** Object:  StoredProcedure [dbo].[spCardDistribution_with_lane_class]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS OFF
GO
SET QUOTED_IDENTIFIER OFF
GO


CREATE PROCEDURE [dbo].[spCardDistribution_with_lane_class]
	@boardId BIGINT,
	@userId BIGINT,
	@rollupLanesString NVARCHAR(MAX) = '',
	@excludedLanesString NVARCHAR(MAX) = '',
	@includedTagsString NVARCHAR(MAX) = '',
	@excludedTagsString NVARCHAR(MAX) = '',
	@includedCardTypesString NVARCHAR(MAX) = '',
	@includedClassesOfServiceString NVARCHAR(MAX) = '',
	@organizationId BIGINT
AS
BEGIN
	SET NOCOUNT ON;

	INSERT INTO [dbo].[fact_ReportExecution] ([ReportName], [OrgId], [UserId], [BoardId], [ExecutionDate])
	VALUES ('Card Distribution', @organizationId, @userId, @boardId, GETUTCDATE())

	DECLARE @returnTable TABLE
		(
			[Card Id] BIGINT NOT NULL,
			[Type] NVARCHAR(64) NOT NULL,
			[Priority] VARCHAR(8) NOT NULL,
			[Class of Service] NVARCHAR(255) NOT NULL,
			[Size] INT NOT NULL,
			[Lane Title] NVARCHAR(255) NOT NULL,
			[Parent Lane Title] NVARCHAR(255) NULL,
			[Lane Id] BIGINT NOT NULL,
			[Lane Class] NVARCHAR(12)
		)

	--Asserts organization has access to the board, else return empty data
	IF @organizationId <> (SELECT [OrgId] FROM [udtf_CurrentBoards](@boardId))
	BEGIN
		SELECT * FROM @returnTable
		RETURN
	END

	--Assert user has access to the board, else return empty data
	IF (SELECT [dbo].[fnGetUserBoardRole](@boardId, @userId)) = 0
	BEGIN
		SELECT * FROM @returnTable
		RETURN
	END

	DECLARE @useIncludeTagTable BIT
	DECLARE @useExcludeTagTable BIT

	DECLARE @orgLanes TABLE
	(
		[LaneId] BIGINT,
		[LaneTitle] NVARCHAR(255),
		[ParentLaneId] BIGINT,
		[ParentLaneTitle] NVARCHAR(255),
		[LaneTypeId] INT,
		[IsDrillThroughDoneLane] BIT
	)

	INSERT INTO @orgLanes
	([LaneId], [LaneTitle], [ParentLaneId], [LaneTypeId], [IsDrillThroughDoneLane])
	SELECT
		LaneId,
		Title,
		ParentLaneId,
		LaneTypeId,
		IsDrillThroughDoneLane
	FROM
	[dbo].[udtf_CurrentLanes](@boardId)

	UPDATE @orgLanes
	SET ParentLaneTitle = [L].LaneTitle
	FROM @orgLanes [L]
	WHERE [L].LaneId = ParentLaneId

	/* Region (Get Card Data)  */
	BEGIN
		INSERT INTO @returnTable
		SELECT
		DISTINCT [Card].[CardId] as [Card Id],
		[CardTypes].[Name],
		(CASE [Card].[Priority] WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS [Priority],
		(CASE WHEN [ClassOfService].[Title] IS NULL THEN 'Not Set' ELSE [ClassOfService].[Title] END) as [Class of Service],
		(CASE WHEN ([Card].[Size] = 0 OR [Card].[Size] IS NULL) THEN 1 ELSE [Card].[Size] END) AS [Size],
		[Lane].[LaneTitle] as [Lane Title],
		[ParentLane].[Title] as [Parent Lane Title],
		[Lane].[LaneId] as [Lane Id],
		CASE 
			WHEN [Lane].[LaneTypeId] = 1 THEN 'Not Started'
			WHEN [Lane].[LaneTypeId] = 0 AND [Lane].[IsDrillThroughDoneLane] = 0 THEN 'Started'
			WHEN [Lane].[LaneTypeId] = 0 AND [Lane].[IsDrillThroughDoneLane] = 1 THEN 'Finished'
			WHEN [Lane].[LaneTypeId] = 2 THEN 'Finished'
			ELSE 'Unknown'
		   END AS [Lane Class]

		FROM [dbo].[udtf_CurrentCards_0_3](@boardId) as [Card]

				--this join eliminates dup open containments
				join	
               (select max(ContainmentStartDate) as maxdim, [CardId] from 
                [dbo].[udtf_CurrentCards_0_3](@boardId)
                group by [CardId]) dup on [Card].ContainmentStartDate = dup.maxdim
				and 
				[Card].CardId = dup.CardId


		JOIN [dbo].[udtf_CurrentCardTypes](@boardId) [CardTypes]
		ON [CardTypes].[CardTypeId] = [Card].[TypeId]
		LEFT JOIN [dbo].[udtf_CurrentClassesOfService](@boardId) [ClassOfService]
		ON [ClassOfService].[ClassOfServiceId] = [Card].[ClassOfServiceId]
		JOIN @orgLanes as [Lane]
		ON [Lane].[LaneId] = [Card].[LaneId]
		LEFT JOIN [dbo].[udtf_CurrentLanes](@boardId) as [ParentLane]
		ON [Lane].[ParentLaneId] = [ParentLane].[LaneId]
		JOIN [fnGetDefaultCardTypes](@boardId, @includedCardTypesString) CT 
		ON CT.CardTypeId = [Card].[TypeId] --Filter on Card Type
		WHERE [Lane].[LaneId] NOT IN (SELECT * FROM [fnSplitLaneParameterString](@excludedLanesString)) --Filter lanes from @excludedLanesString
		AND ISNULL([Card].[ClassOfServiceId], 0) IN (SELECT ISNULL(ClassOfServiceId, 0) FROM  [fnGetDefaultClassesOfService](@boardId, @includedClassesOfServiceString)) --Filter on Class of Service
	END
	/* Region */

	/* Region (Filter Include and Exclude Tags)  */
	BEGIN
		IF (NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL OR NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL)
		BEGIN
			-- Refresh the card tag cache
			EXECUTE [dbo].[usp_RefreshBoardCardCache] @boardId, 1
		END

		--Filter on Included Tags
		IF NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL
		BEGIN
			DELETE FROM @returnTable
			WHERE [Card Id] NOT IN
			(SELECT [CardId] FROM [fnGetTagsList](@boardId, @includedTagsString))
		END
		--Filter on Excluded Tags
		IF NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL
		BEGIN
			DELETE FROM @returnTable
			WHERE [Card Id] IN
			(SELECT [CardId] FROM [fnGetTagsList](@boardId, @excludedTagsString))
		END
	END
	/* Region */

	/* Region (Child Lane Rollups)  */
	BEGIN
		DECLARE @childToParentMappingForRollup TABLE
		(
			ChildLaneId BIGINT,
			RollupLaneId BIGINT,
			RollupLaneTitle NVARCHAR(255),
			RollupLaneTypeId INT,
			RollupParentLaneId BIGINT
			PRIMARY KEY (ChildLaneId, RollupLaneId)
		)

		INSERT INTO @childToParentMappingForRollup
		SELECT sub.[LaneId] AS [ChildLaneId], glo.[LaneId] AS [RollupLaneId], glo.[LaneTitle] AS [RollupLaneTitle], glo.[LaneTypeId] AS [RollupLaneTypeId], glo.ParentLaneId AS [RollupParentLaneId]--, glo.[PathString]--, sub.[LaneId], sub.[LaneTitle], sub.[PathString]
		FROM [dbo].[fnGetLaneOrder](@boardId) glo
		INNER JOIN [fnSplitLaneParameterString](@rollupLanesString) slps
			ON glo.[LaneId] = slps.[LaneId]
		INNER JOIN (
			SELECT b.[LaneId], b.[LaneTitle], b.[PathString] FROM [dbo].[fnGetLaneOrder](@boardId) b
		) sub
			ON sub.[PathString] LIKE glo.[PathString] + '%' AND LEN(sub.[PathString]) <> LEN(glo.[PathString])

		IF EXISTS (SELECT TOP 1 [ChildLaneId] FROM @childToParentMappingForRollup)
		BEGIN
			--PRINT 'Updating return table'
			--Rename child lanes to their parent, set child lane id to parent lane id
			UPDATE rt
			SET rt.[Lane Id] = ru.[RollupLaneId]
			, rt.[Lane Title] = ru.[RollupLaneTitle]
			, rt.[Parent Lane Title] = PL.LaneTitle
			FROM @returnTable AS rt
			INNER JOIN @childToParentMappingForRollup ru
				ON rt.[Lane Id] = ru.[ChildLaneId]
			LEFT JOIN @orgLanes PL
				ON PL.LaneId = ru.RollupParentLaneId
		END
	END
	/* Region */

	/* Region (Return Data) */
	SELECT * FROM @returnTable
	/* Region */
END




GO
/****** Object:  StoredProcedure [dbo].[spCardDistributionByUser]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




CREATE PROCEDURE [dbo].[spCardDistributionByUser]
	@boardId BIGINT,
	@userId BIGINT,
	@excludedLanesString NVARCHAR(MAX) = '',
	@includedTagsString NVARCHAR(MAX) = '',
	@excludedTagsString NVARCHAR(MAX) = '',
	@includedCardTypesString NVARCHAR(MAX) = '',
	@includedClassesOfServiceString NVARCHAR(MAX) = '',
	@organizationId BIGINT
AS
BEGIN
	SET NOCOUNT ON;

	INSERT INTO [dbo].[fact_ReportExecution] ([ReportName], [OrgId], [UserId], [BoardId], [ExecutionDate])
	VALUES ('Card Distribution By User)', @organizationId, @userId, @boardId, GETUTCDATE())

	declare @unionTable table ([Card Id] BIGINT NOT NULL,
		[Size] INT NOT NULL,
		[User Email] NVARCHAR(MAX) NOT NULL);

	DECLARE @filteredCardsForBoard TABLE
	(
		[Card Id] BIGINT NOT NULL,
		[Size] INT NOT NULL,
		primary key([Card Id])
	)

	--Asserts organization has access to the board, else return empty data
	IF @organizationId <> (SELECT [OrganizationId] FROM [udtf_CurrentBoards_0_2](@boardId))
	BEGIN
		SELECT * FROM @unionTable;
		RETURN
	END

	--Assert user has access to the board, else return empty data
	IF (SELECT [dbo].[fnGetUserBoardRole_0_2](@boardId, @userId)) = 0
	BEGIN
		SELECT * FROM @unionTable;
		RETURN
	END

	/* Region (Get Card Data)  */
	insert into @filteredCardsForBoard
		SELECT 
				[Card].[CardId] AS [Card Id]
				, [Card].[Size] AS [Size]
		FROM 		[dbo].[udtf_CurrentCards_0_2](@boardId) [Card]
		LEFT JOIN 	[dbo].[udtf_CurrentLanes_0_2](@boardId) [Lane]
				ON [Lane].[LaneId] = [Card].[LaneId]
		INNER JOIN 	[fnGetDefaultCardTypes_0_2](@boardId, @includedCardTypesString) CT
				ON CT.CardTypeId = [Card].[TypeId]--Filter on Card Type
		WHERE
	 			[Lane].[LaneId] NOT IN (
					SELECT 	* 
					FROM 	[fnSplitLaneParameterString_0_2](@excludedLanesString)
				)
		AND 		ISNULL([Card].[ClassOfServiceId], 0) IN (
					SELECT ISNULL(ClassOfServiceId, 0) 
					FROM  [fnGetDefaultClassesOfService_0_2](@boardId, @includedClassesOfServiceString)
				) --Filter on Class of Service
	
	/* Region */

	/* Region (Filter Include and Exclude Tags)  */
	BEGIN
		IF (NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL OR NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL)
		BEGIN
			-- Refresh the card tag cache
			EXECUTE [dbo].[usp_RefreshBoardCardCache] @boardId, 1
		END

		--Filter on Included Tags
		IF NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL
		BEGIN
			DELETE FROM @filteredCardsForBoard
			WHERE [Card Id] NOT IN
			(SELECT [CardId] FROM [fnGetTagsList_0_2](@boardId, @includedTagsString))
		END
		--Filter on Excluded Tags
		IF NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL
		BEGIN
			DELETE FROM @filteredCardsForBoard
			WHERE [Card Id] IN
			(SELECT [CardId] FROM [fnGetTagsList_0_2](@boardId, @excludedTagsString))
		END
	END

	--select * from @filteredCardsForBoard where [Card Id] = 167043435;

	--get distinct list of cards that are assigned
	declare @assignedCards table (CardId bigint, [Size] INT NOT NULL, 
		ToUserId bigint, primary key([CardId], [ToUserId]));
	insert into @assignedCards (CardId, Size, ToUserId)
		select DISTINCT [Card].[Card Id], [Card].Size, 
			[Assignment].ToUserID from @filteredCardsForBoard [Card]
			left join [fact_UserAssignmentContainmentPeriod] [Assignment]
				ON [Card].[Card Id] = [Assignment].[CardID]
				where [Assignment].ContainmentEndDate is NULL
				and [Assignment].ToUserID is not null;

	declare @unAssignedCards table (CardId bigint, [Size] int not null, primary key([CardId]));
	insert into @unAssignedCards (CardId, Size)
		select [Card Id], Size from @filteredCardsForBoard
			except select un.CardId, un.Size from 
				(select CardId, Size from @assignedCards group by CardId, Size) un;

	insert into @unionTable ([Card Id], [Size], [User Email])
	SELECT [Card].[CardId] as [Card Id], (CASE [Card].[Size] 
					WHEN 0 THEN 1 
					ELSE [Card].[Size]
				END) AS [Size], [User].[EmailAddress]
				 AS [User Email] 
		FROM @assignedCards [Card]
			INNER JOIN 	[dbo].[udtf_CurrentUsersInOrg_0_2](@organizationId) [User]
				ON [User].[UserId] = [Card].[ToUserID]
				
	insert into @unionTable ([Card Id], [Size], [User Email])
	select [CardId] as [Card Id], (CASE [Size] 
					WHEN 0 THEN 1 
					ELSE [Size]
				END) AS [Size], '* Not Assigned' as [User Email]
		from @unAssignedCards


	--union
	--select 309063145  as 'Card Id',1 as 'Size', '* Not Assigned' as 'User Id'

	select * from @unionTable order by [Card Id]
END








GO
/****** Object:  StoredProcedure [dbo].[spCardDistributionByUser_with_lane_class]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[spCardDistributionByUser_with_lane_class]
    @boardId BIGINT,
    @userId BIGINT,
    @excludedLanesString NVARCHAR(MAX) = '',
    @includedTagsString NVARCHAR(MAX) = '',
    @excludedTagsString NVARCHAR(MAX) = '',
    @includedCardTypesString NVARCHAR(MAX) = '',
    @includedClassesOfServiceString NVARCHAR(MAX) = '',
    @organizationId BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO [dbo].[fact_ReportExecution] ([ReportName], [OrgId], [UserId], [BoardId], [ExecutionDate])
    VALUES ('Card Distribution By User)', @organizationId, @userId, @boardId, GETUTCDATE())
    declare @unionTable table ([Card Id] BIGINT NOT NULL,
        [Size] INT NOT NULL,
        [Lane Class] nvarchar(12) not null,
        [User Email] NVARCHAR(MAX) NOT NULL);
    DECLARE @filteredCardsForBoard TABLE
    (
    [DimRowId] BIGINT,
        [Card Id] BIGINT NOT NULL,
        [Size] INT NOT NULL,
        [Lane Class] nvarchar(12) not null
        ,primary key([Card Id])
    )
    --Asserts organization has access to the board, else return empty data
    IF @organizationId <> (SELECT [OrganizationId] FROM [udtf_CurrentBoards_0_2](@boardId))
    BEGIN
        SELECT * FROM @unionTable;
        RETURN
    END
    --Assert user has access to the board, else return empty data
    IF (SELECT [dbo].[fnGetUserBoardRole_0_2](@boardId, @userId)) = 0
    BEGIN
        SELECT * FROM @unionTable;
        RETURN
    END
    /* Region (Get Card Data)  */
    insert into @filteredCardsForBoard
        SELECT [Card].[DimRowId]
                ,[Card].[CardId] AS [Card Id]
                , [Card].[Size] AS [Size]
        ,CASE 
            WHEN [Lane].[LaneTypeId] = 1 THEN 'Not Started'
            WHEN [Lane].[LaneTypeId] = 0 AND [Lane].[IsDrillThroughDoneLane] = 0 THEN 'Started'
            WHEN [Lane].[LaneTypeId] = 0 AND [Lane].[IsDrillThroughDoneLane] = 1 THEN 'Finished'
            WHEN [Lane].[LaneTypeId] = 2 THEN 'Finished'
            ELSE 'Unknown'
           END AS [Lane Class]
        FROM        [dbo].[udtf_CurrentCards_0_3](@boardId) [Card]

				--this join eliminates dup open containments
				join	
               (select max(ContainmentStartDate) as maxdim, [CardId] from 
                [dbo].[udtf_CurrentCards_0_3](@boardId)
                group by [CardId]) dup on [Card].ContainmentStartDate = dup.maxdim
				and 
				[Card].CardId = dup.CardId

        LEFT JOIN   [dbo].[udtf_CurrentLanes_0_2](@boardId) [Lane]
                ON [Lane].[LaneId] = [Card].[LaneId]
        INNER JOIN  [fnGetDefaultCardTypes_0_2](@boardId, @includedCardTypesString) CT
                ON CT.CardTypeId = [Card].[TypeId]--Filter on Card Type
        WHERE
                [Lane].[LaneId] NOT IN (
                    SELECT  * 
                    FROM    [fnSplitLaneParameterString_0_2](@excludedLanesString)
                )
        AND         ISNULL([Card].[ClassOfServiceId], 0) IN (
                    SELECT ISNULL(ClassOfServiceId, 0) 
                    FROM  [fnGetDefaultClassesOfService_0_2](@boardId, @includedClassesOfServiceString)
                ) --Filter on Class of Service
    
    /* Region (Filter Include and Exclude Tags)  */
    BEGIN
        IF (NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL OR NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL)
        BEGIN
            -- Refresh the card tag cache
            EXECUTE [dbo].[usp_RefreshBoardCardCache] @boardId, 1
        END
        --Filter on Included Tags
        IF NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL
        BEGIN
            DELETE FROM @filteredCardsForBoard
            WHERE [Card Id] NOT IN
            (SELECT [CardId] FROM [fnGetTagsList_0_2](@boardId, @includedTagsString))
        END
        --Filter on Excluded Tags
        IF NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL
        BEGIN
            DELETE FROM @filteredCardsForBoard
            WHERE [Card Id] IN
            (SELECT [CardId] FROM [fnGetTagsList_0_2](@boardId, @excludedTagsString))
        END
    END
    --select * from @filteredCardsForBoard where [Card Id] = 167043435;
    --get distinct list of cards that are assigned
    DECLARE @assignedCards TABLE (CardId BIGINT, [Size] INT NOT NULL, [Lane Class] NVARCHAR(12) NOT NULL,
        ToUserId BIGINT);
    INSERT INTO @assignedCards (CardId, Size, [Lane Class], ToUserId)
        SELECT DISTINCT [Card].[Card Id], [Card].Size, [Card].[Lane Class],
            [Assignment].ToUserID FROM @filteredCardsForBoard [Card]
            LEFT JOIN [fact_UserAssignmentContainmentPeriod] [Assignment]
                ON [Card].[Card Id] = [Assignment].[CardID]
                WHERE [Assignment].ContainmentEndDate IS NULL
				AND [Assignment].IsApproximate = 0
                AND [Assignment].ToUserID IS NOT NULL;
    DECLARE @unAssignedCards TABLE (CardId BIGINT --INDEX idx_card_id2 CLUSTERED
    , [Size] INT NOT NULL, 
    [Lane Class] NVARCHAR(12) NOT NULL
    , PRIMARY KEY([CardId])
    );
    INSERT INTO @unAssignedCards (CardId, Size, [Lane Class])
        SELECT [Card Id], Size, [Lane Class] FROM @filteredCardsForBoard
            EXCEPT SELECT un.CardId, un.Size, un.[Lane Class] FROM 
                (SELECT CardId, Size,[Lane Class] FROM @assignedCards GROUP BY CardId, Size, [Lane Class]) un;
    INSERT INTO @unionTable ([Card Id], [Size], [Lane Class], [User Email])
    SELECT [Card].[CardId] AS [Card Id], (CASE [Card].[Size] 
                    WHEN 0 THEN 1 
                    ELSE [Card].[Size]
                END) AS [Size]
                , [Card].[Lane Class]
                , [User].[EmailAddress]
                 AS [User Email] 
        FROM @assignedCards [Card]
            INNER JOIN  [dbo].[udtf_CurrentUsersInOrg_0_2](@organizationId) [User]
                ON [User].[UserId] = [Card].[ToUserID]
                
    INSERT INTO @unionTable ([Card Id], [Size], [Lane Class], [User Email])
    SELECT [CardId] AS [Card Id], (CASE [Size] 
                    WHEN 0 THEN 1 
                    ELSE [Size]
                END) AS [Size]
                , [Lane Class]
                , '* Not Assigned' AS [User Email]
        FROM @unAssignedCards
    --union
    --select 309063145  as 'Card Id',1 as 'Size', '* Not Assigned' as 'User Id'
    SELECT * FROM @unionTable ORDER BY [Card Id]
END




GO
/****** Object:  StoredProcedure [dbo].[spCFD]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[spCFD] (
	@boardId BIGINT,
	@userId BIGINT,
	@startDate DATETIME = NULL,
	@endDate DATETIME = NULL,
 	@rollupLanesString NVARCHAR(MAX) = '',
	@excludedLanesString NVARCHAR(MAX) = '',
	@includedTagsString NVARCHAR(MAX) = '',
	@excludedTagsString NVARCHAR(MAX) = '',
	@includedCardTypesString NVARCHAR(MAX) = '',
	@includedClassesOfServiceString NVARCHAR(MAX) = '',
	@offsetHours INT = 0,
	@organizationId BIGINT
	)
AS
BEGIN

	SET NOCOUNT ON;

	INSERT INTO [dbo].[fact_ReportExecution] ([ReportName], [OrgId], [UserId], [BoardId], [ExecutionDate])
	VALUES ('Flow Dashboard', @organizationId, @userId, @boardId, GETUTCDATE())

	DECLARE @laneCountRecords TABLE (
			[LaneId] BIGINT,
			[LaneTitle] NVARCHAR(255),
			[LaneTypeId] INT,
			[MeasureDate] DATETIME,
			[CardCount] INT,
			[CardSize] INT,
			[OrderBy] INT,
			[MinCardCount] INT,
			[MinCardSize] INT
		)
		
	IF @organizationId <> (SELECT [OrganizationId] FROM [udtf_CurrentBoards_0_2](@boardId))
	BEGIN
		SELECT * FROM @laneCountRecords
		RETURN
	END

		--Assert user has access to the board, else return empty data
	IF (SELECT [dbo].[fnGetUserBoardRole_0_2](@boardId, @userId)) = 0
	BEGIN
		SELECT * FROM @laneCountRecords
		RETURN
	END

		DECLARE @useIncludeTagTable BIT
		DECLARE @useExcludeTagTable BIT
		DECLARE @minDate DATETIME
		DECLARE @maxDate DATETIME
		DECLARE @endDateOrdinal BIGINT

BEGIN /* Region (Min and Max Date Calculations) */

		IF (@startDate IS NULL)
		BEGIN
			SELECT @minDate = [dbo].[fnGetMinimumDate_0_2](@boardId,@offsetHours)
		END 
		ELSE 
		BEGIN 
			SELECT @minDate = @startDate
		END

		IF (@endDate IS NULL)
		BEGIN
			SELECT @endDateOrdinal = ((CAST(dt.[Id] AS BIGINT) * 100000) + (3600 * @offsetHours))
				, @maxDate = DATEADD(HOUR, @offsetHours, dt.[Date])
			FROM [dim_Date] dt
			WHERE dt.[Date] = CONVERT(DATETIME, DATEDIFF(DAY, 0, GETUTCDATE()))
		END 
		ELSE 
		BEGIN
			SELECT @endDateOrdinal = ((CAST(dt.[Id] AS BIGINT) * 100000) + (3600 * @offsetHours))
				, @maxDate = DATEADD(HOUR, @offsetHours, dt.[Date])
			FROM [dim_Date] dt
			WHERE dt.[Date] = @endDate 
		END

END /* Region */

BEGIN /* Region (Include and Exclude Tags)  */
		SELECT @useIncludeTagTable = 0, @useExcludeTagTable = 0

		

		DECLARE @cardWithIncludeTags TABLE
		(
			CardId BIGINT
		)

		DECLARE @cardWithExcludeTags TABLE
		(
			CardId BIGINT
		)


		IF (NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL OR NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL)
		BEGIN
			-- Refresh the card tag cache
			EXECUTE [dbo].[usp_RefreshBoardCardCache] @boardId, 1
		END

		IF NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL
		BEGIN
			SET @useIncludeTagTable = 1

			INSERT INTO @cardWithIncludeTags
			SELECT [CardId]
			FROM [fnGetTagsList_0_2](@boardId, @includedTagsString)
		END

		IF NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL
		BEGIN
			SET @useExcludeTagTable = 1

			INSERT INTO @cardWithExcludeTags
			SELECT [CardId]
			FROM [fnGetTagsList_0_2](@boardId, @excludedTagsString)

			--PRINT 'Using Exclude Tags'
		END
END /* Region */

BEGIN /* Region (Child Lane Rollups)  */
		DECLARE @childToParentMappingForRollup TABLE
		(
			ChildLaneId BIGINT,
			RollupLaneId BIGINT,
			RollupLaneTitle NVARCHAR(255),
			RollupLaneTypeId INT,
			PRIMARY KEY (ChildLaneId, RollupLaneId)
		)

		INSERT INTO @childToParentMappingForRollup
		SELECT sub.[LaneId] AS [ChildLaneId], glo.[LaneId] AS [RollupLaneId], glo.[LaneTitle] AS [RollupLaneTitle], glo.[LaneTypeId] AS [RollupLaneTypeId]--, glo.[PathString]--, sub.[LaneId], sub.[LaneTitle], sub.[PathString]
		FROM [dbo].[fnGetLaneOrder_0_2](@boardId) glo
		INNER JOIN [fnSplitLaneParameterString_0_2](@rollupLanesString) slps
			ON glo.[LaneId] = slps.[LaneId]
		INNER JOIN (
			SELECT b.[LaneId], b.[LaneTitle], b.[PathString] FROM [dbo].[fnGetLaneOrder_0_2](@boardId) b
		) sub
			ON sub.[PathString] LIKE glo.[PathString] + '%' AND LEN(sub.[PathString]) <> LEN(glo.[PathString])

END /* Region */
		
BEGIN /* Region (Date Filtering)  */
		DECLARE @dateTable TABLE (
			[Date] DATETIME
			, DateCompareOrdinal BIGINT
		)

		--Insert the dates and the corresponding ordinals into a TABLE
		INSERT INTO @dateTable
		SELECT  DT.[Date]
		      , ((CAST(dt.[Id] AS BIGINT) * 100000) + (3600 * @offsetHours))
		FROM [dim_Date] DT
		WHERE DT.[Date] BETWEEN @minDate AND @maxDate
		
END /* Region */

BEGIN /* Region (Card Filtering)  */
		
		DECLARE @filteredCards TABLE (
			Id BIGINT,
			Size INT
		)
		INSERT INTO @filteredCards
		SELECT
		C.CardId, 
		C.Size
		FROM [dbo].[udtf_CurrentCards_0_2](@boardId) C
		JOIN [dbo].[udtf_CurrentLanes_0_2](@boardId) L ON C.LaneId = L.LaneId
		LEFT JOIN @cardWithIncludeTags IT ON IT.CardId = C.CardId
		LEFT JOIN @cardWithExcludeTags ET ON ET.CardId = C.CardId
		JOIN [fnGetDefaultCardTypes_0_2](@boardId, @includedCardTypesString) CT ON CT.CardTypeId = C.TypeID
		WHERE L.BoardId = @boardId
			AND C.CardId = (CASE WHEN @useIncludeTagTable = 1 THEN IT.CardId ELSE C.CardId END)
			AND ((@useExcludeTagTable = 1 AND ET.CardId IS NULL) OR @useExcludeTagTable = 0)
			AND ISNULL(C.ClassOfServiceId,0) IN (SELECT ISNULL(ClassOfServiceId,0) FROM  [fnGetDefaultClassesOfService_0_2](@boardId, @includedClassesOfServiceString))


END /* Region */

BEGIN /* Region (Collect the Data)  */

		INSERT INTO @laneCountRecords
		SELECT ISNULL(RL.RollupLaneId, CP.LaneId) AS LaneId
		  , ISNULL(RL.RollupLaneTitle, L.Title) AS LaneTitle
		  , L.LaneTypeId AS LaneTypeId
		  , DT.[Date] AS MeasureDate
		  , COUNT(*) AS CardCount
		  , SUM(CASE WHEN C.Size IS NULL OR C.Size = 0 THEN 1 ELSE C.Size END) AS CardSize
		  , [LaneRank] AS OrderBy
		  , 0 AS MinCardCount
		  , 0 AS MinCardSize
	  FROM [fact_CardLaneContainmentPeriod] CP
	  JOIN @dateTable DT ON DT.DateCompareOrdinal 
									BETWEEN CP.[StartOrdinal] AND ISNULL(CP.[EndOrdinal], @endDateOrdinal)
	  JOIN @filteredCards C ON CP.CardID = C.Id
	  JOIN [dbo].[udtf_CurrentLanes_0_2](@boardId) L ON CP.LaneId = L.LaneId
	  LEFT JOIN @childToParentMappingForRollup RL ON RL.ChildLaneId = CP.LaneID
	  JOIN [fnGetLaneOrder_0_2](@boardId) O ON O.LaneID = ISNULL(RL.RollupLaneId, CP.LaneID)
	  WHERE  L.LaneId NOT IN (SELECT LaneID FROM [fnSplitLaneParameterString_0_2](@excludedLanesString))
	  GROUP BY ISNULL(RL.RollupLaneId, CP.LaneId)
		  ,  ISNULL(RL.RollupLaneTitle, L.Title)
		  , L.LaneTypeId 
		  , DT.[Date]
		  , O.[LaneRank]
	  HAVING  ISNULL(RL.RollupLaneId, CP.LaneId) NOT IN (SELECT [ChildLaneId] 
												  FROM @childToParentMappingForRollup)

END /* Region  */

BEGIN /* Region (Update with the minimum size/count)    */
     
      --Now that we have the Counts and Sizes By day, we need to determine the minimum values
      --across all days.
      UPDATE @laneCountRecords
        SET MinCardCount = CASE WHEN @startDate < M.MinDateOfLaneRecords THEN 0 ELSE M.MinCardCount END
            ,MinCardSize = CASE WHEN @startDate < M.MinDateOfLaneRecords THEN 0 ELSE M.MinCardSize END
      FROM @laneCountRecords LC
      JOIN (SELECT LaneId
            , MIN( CardCount) AS MinCardCount
            , MIN(CardSize) AS MinCardSize
            , MIN(MeasureDate) AS MinDateOfLaneRecords
            FROM @laneCountRecords
            GROUP BY LaneId) M ON M.LaneId = LC.LaneId
END /* Region   */

BEGIN /* Region (Select the resultset with filler) */
	INSERT INTO @laneCountRecords
	 SELECT L.LaneId AS LaneId
		, L.Title AS LaneTitle
		, L.LaneTypeId AS LaneTypeId
		, DT.[Date] AS MeasureDate
		, 0 AS CardCount
		, 0 AS CardSize
		, [LaneRank] AS OrderBy
		, 0 AS MinCardCount
		, 0 AS MinCardSize
		FROM [dbo].[udtf_CurrentLanes_0_2](@boardId) L
		JOIN [fnGetLaneOrder_0_2](@boardId) O ON O.LaneID = L.LaneId
		CROSS JOIN @dateTable DT
		WHERE L.LaneId NOT IN (SELECT LaneID FROM [fnSplitLaneParameterString_0_2](@excludedLanesString))
		AND DT.[Date] BETWEEN @minDate AND @maxDate

END /* Region  */
END


IF (SELECT SUM(CardCount) FROM @laneCountRecords) = 0
BEGIN
	DELETE FROM @laneCountRecords
END

SELECT * FROM @laneCountRecords
		ORDER BY OrderBy,
		 MeasureDate





GO
/****** Object:  StoredProcedure [dbo].[spEfficiencyDiagram]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[spEfficiencyDiagram]
	@boardId BIGINT,
	@userId BIGINT,
	@minDate DATE = NULL,
	@maxDate DATE = NULL,
	@excludedLanesString NVARCHAR(MAX) = '',
	@includedTagsString NVARCHAR(MAX) = '',
	@excludedTagsString NVARCHAR(MAX) = '',
	@includedCardTypesString NVARCHAR(MAX) = '',
	@includedClassesOfServiceString NVARCHAR(MAX) = '',
	@offsetHours INT = 0,
	@organizationId BIGINT
AS
BEGIN
	SET NOCOUNT ON

	INSERT INTO [dbo].[fact_ReportExecution] ([ReportName], [OrgId], [UserId], [BoardId], [ExecutionDate])
	VALUES ('Efficiency', @organizationId, @userId, @boardId, GETUTCDATE())

	DECLARE @returnTable TABLE
	(
		[Date] DATE,
		[Lane Type] VARCHAR(12),
		[Number of Cards] BIGINT,
		[Total Size of Cards] INT
	)

	--Asserts organization has access to the board, else return empty data
	IF @organizationId <> (SELECT [OrgId] FROM [dbo].[udtf_CurrentBoards](@boardId))
	BEGIN
		SELECT * FROM @returnTable
		RETURN
	END

	--Assert user has access to the board, else return empty data
	IF (SELECT [dbo].[fnGetUserBoardRole](@boardId, @userId)) = 0
	BEGIN
		SELECT * FROM @returnTable
		RETURN
	END

	    DECLARE @useIncludeTagTable BIT
		DECLARE @useExcludeTagTable BIT
		DECLARE @maxDateOrdinal BIGINT

BEGIN /* Region (Min and Max Date Calculations) */

		IF (@minDate IS NULL)
		BEGIN
			SELECT @minDate = [dbo].[fnGetMinimumDate](@boardId,@offsetHours)
		END 
		ELSE 
		BEGIN 
			SELECT @minDate = @minDate
		END

		IF (@maxDate IS NULL)
		BEGIN
			SELECT @maxDateOrdinal = ((CAST(dt.[Id] AS BIGINT) * 100000) + (3600 * ISNULL(@offsetHours,0)))
				, @maxDate = DATEADD(HOUR, ISNULL(@offsetHours,0), dt.[Date])
			FROM [dim_Date] dt
			WHERE dt.[Date] = Convert(DATETIME, DATEDIFF(DAY, 0, GETUTCDATE()))
		END 
		ELSE 
		BEGIN
			SELECT @maxDateOrdinal = ((CAST(dt.[Id] AS BIGINT) * 100000) + (3600 * ISNULL(@offsetHours,0)))
				, @maxDate = DATEADD(HOUR, ISNULL(@offsetHours,0), dt.[Date])
			FROM [dim_Date] dt
			WHERE dt.[Date] = CONVERT(DATETIME, DATEDIFF(DAY, 0, @maxDate)) 
		END

END /* Region */

BEGIN /* Region (Include and Exclude Tags)  */
		SELECT @useIncludeTagTable = 0, @useExcludeTagTable = 0

		

		DECLARE @cardWithIncludeTags TABLE
		(
			CardId BIGINT
		)

		DECLARE @cardWithExcludeTags TABLE
		(
			CardId BIGINT
		)

		IF (NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL OR NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL)
		BEGIN
			-- Refresh the card tag cache
			EXECUTE [dbo].[usp_RefreshBoardCardCache] @boardId, 1
		END

		IF NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL
		BEGIN
			SET @useIncludeTagTable = 1

			INSERT INTO @cardWithIncludeTags
			SELECT [CardId]
			FROM [fnGetTagsList](@boardId,@includedTagsString)
		END

		IF NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL
		BEGIN
			SET @useExcludeTagTable = 1

			INSERT INTO @cardWithExcludeTags
			SELECT [CardId]
			FROM [fnGetTagsList](@boardId,@excludedTagsString)

			--PRINT 'Using Exclude Tags'
		END
END /* Region */

BEGIN /* Region (Date Filtering)  */
		DECLARE @dateTable TABLE (
			[Date] DATE
			, DateCompareOrdinal BIGINT
		)

		--Insert the dates and the corresponding ordinals into a TABLE
		INSERT INTO @dateTable
		SELECT  DT.[Date]
		      , ((CAST(dt.[Id] AS BIGINT) * 100000) + (3600 * ISNULL(@offsetHours,0)))
		FROM [dim_Date] DT
		WHERE DT.[Date] BETWEEN @minDate AND @maxDate

		

END /* Region */

BEGIN /* Region (Card Filtering)  */
		
		DECLARE @filteredCards TABLE (
			Id BIGINT,
			Size INT
		)
		INSERT INTO @filteredCards
		SELECT
		C.CardId, 
		CASE WHEN C.Size = 0 THEN 1 ELSE C.Size END
		FROM [dbo].[udtf_CurrentCards](@boardId) C
		JOIN [dbo].[udtf_CurrentLanes](@boardId) L ON C.LaneId = L.LaneId
		LEFT JOIN @cardWithIncludeTags IT ON IT.CardId = C.CardId
		LEFT JOIN @cardWithExcludeTags ET ON ET.CardId = C.CardId
		JOIN [fnGetDefaultCardTypes](@boardId, @includedCardTypesString) CT ON CT.CardTypeId = C.TypeID
		WHERE C.CardId = (CASE WHEN @useIncludeTagTable = 1 THEN IT.CardId ELSE C.CardId END)
			AND ((@useExcludeTagTable = 1 AND ET.CardId IS NULL) OR @useExcludeTagTable = 0)
			AND ISNULL(C.ClassOfServiceId,0) IN (SELECT ISNULL(ClassOfServiceId,0) FROM  [fnGetDefaultClassesOfService](@boardId, @includedClassesOfServiceString))


END /* Region */
------

	SELECT DT.[Date]
		   , CASE L.[Type]
			 WHEN 99 THEN 'Untyped'
			 WHEN 1 THEN 'Ready'
			 WHEN 2 THEN 'InProcess'
			 WHEN 3 THEN 'Completed'
			 ELSE 'Untyped' END AS [Lane Type]
		   , COUNT(C.Id) AS [Number of Cards]
		   , SUM(C.Size) AS [Total Size of Cards]
	FROM [fact_CardLaneContainmentPeriod] CP
	     JOIN @dateTable DT ON DT.DateCompareOrdinal 
									BETWEEN CP.[StartOrdinal] - 1 AND ISNULL(CP.[EndOrdinal], @maxDateOrdinal)
		 JOIN @filteredCards C ON CP.CardID = C.Id
	     JOIN [dbo].[udtf_CurrentLanes](@boardId) L ON CP.LaneId = L.LaneId
    WHERE L.LaneId NOT IN (SELECT LaneID FROM [fnSplitLaneParameterString](@excludedLanesString))
	GROUP BY DT.[Date]
		   , CASE L.[Type]
			 WHEN 99 THEN 'Untyped'
			 WHEN 1 THEN 'Ready'
			 WHEN 2 THEN 'InProcess'
			 WHEN 3 THEN 'Completed'
			 ELSE 'Untyped' END


END




GO
/****** Object:  StoredProcedure [dbo].[spPPC]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[spPPC] (

	@boardId BIGINT,
	@userId BIGINT,
	@startDate DATETIME = NULL,
	@endDate DATETIME = NULL,
	@startLanesString NVARCHAR(MAX) = '',
	--@finishLaneId BIGINT = NULL,
 	--@rollupLanesString NVARCHAR(MAX) = '',
	--@excludedLanesString NVARCHAR(MAX) = '',
	@includedTagsString NVARCHAR(MAX) = '',
	@excludedTagsString NVARCHAR(MAX) = '',
	@includedCardTypesString NVARCHAR(MAX) = '',
	@includedClassesOfServiceString NVARCHAR(MAX) = '',
	@hoursOffset INT = 0,
	@organizationId BIGINT

)

AS

BEGIN

	SET NOCOUNT ON;

	INSERT INTO [dbo].[fact_ReportExecution] ([ReportName], [OrgId], [UserId], [BoardId], [ExecutionDate])
	VALUES ('PPC', @organizationId, @userId, @boardId, GETUTCDATE())

	DECLARE

	@minDate DATETIME,
	@maxDate DATETIME,
	@endDateOrdinal BIGINT,
	@useIncludeTagTable BIT,
	@useExcludeTagTable BIT

	BEGIN 
		DECLARE @dateTable TABLE (
			[Date] DATETIME
			, DateCompareOrdinal BIGINT
		)

	END

	BEGIN 
		DECLARE @CardStatus TABLE (
			CardID BIGINT
			,CardTitle NVARCHAR(255)
			, PlannedStart DATETIME
			, ActualStart DATETIME
			, PlannedFinish DATETIME
			, ActualFinish DATETIME
			, CardStatus varchar(13)
		)

	END

	
	IF @organizationId <> (SELECT [OrganizationId] FROM [udtf_CurrentBoards_0_2](@boardId))
		BEGIN
			SELECT * FROM @CardStatus
			RETURN
		END


	--Assert user has access to the board, else return empty data
	IF (SELECT [dbo].[fnGetUserBoardRole_0_2](@boardId, @userId)) = 0
		BEGIN
			SELECT * FROM @CardStatus
			RETURN
		END

	BEGIN /* Region (Min and Max Date Calculations) */

		IF (@startDate IS NULL)
			BEGIN
				SELECT @minDate = [dbo].[fnGetMinimumDate_0_2](@boardId,@hoursOffset)
			END 
			ELSE 
			BEGIN 
				SELECT @minDate = @startDate
			END

		IF (@endDate IS NULL)
			BEGIN
				SELECT @endDateOrdinal = ((CAST(dt.[Id] AS BIGINT) * 100000) + (3600 * @hoursOffset))
					, @maxDate = DATEADD(HOUR, @hoursOffset, dt.[Date])
				FROM [dim_Date] dt
				WHERE dt.[Date] = CONVERT(DATETIME, DATEDIFF(DAY, 0, GETUTCDATE()))
			END 
		ELSE 
			BEGIN
				SELECT @endDateOrdinal = ((CAST(dt.[Id] AS BIGINT) * 100000) + (3600 * @hoursOffset))
					, @maxDate = DATEADD(HOUR, @hoursOffset, dt.[Date])
				FROM [dim_Date] dt
				WHERE dt.[Date] = @endDate 
			END

	END /* Region */


	BEGIN /* Region (Date Filtering)  */

		INSERT INTO @dateTable
			SELECT  DT.[Date]
				, ((CAST(dt.[Id] AS BIGINT) * 100000) + (3600 *0))
			FROM [dim_Date] DT
			WHERE DT.[Date] BETWEEN @minDate AND @maxDate

	END /*Region*/

		BEGIN /* Region (Card Status Values */
		DECLARE @status TABLE (
			CardStatus varchar(13)
		)

		INSERT INTO @status (CardStatus) VALUES ('Not Completed')
		INSERT INTO @status (CardStatus) VALUES ('Completed')
		INSERT INTO @status (CardStatus) VALUES ('Early')
		INSERT INTO @status (CardStatus) VALUES ('Past Due')

	END /* End Region */

	BEGIN /* Region (Include and Exclude Tags)  */
		SELECT @useIncludeTagTable = 0, @useExcludeTagTable = 0

		

		DECLARE @cardWithIncludeTags TABLE
		(
			CardId BIGINT
		)

		DECLARE @cardWithExcludeTags TABLE
		(
			CardId BIGINT
		)


		IF (NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL OR NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL)
		BEGIN
			-- Refresh the card tag cache
			EXECUTE [dbo].[usp_RefreshBoardCardCache] @boardId, 1
		END

		IF NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL
		BEGIN
			SET @useIncludeTagTable = 1

			INSERT INTO @cardWithIncludeTags
			SELECT [CardId]
			FROM [fnGetTagsList_0_2](@boardId, @includedTagsString)
		END

		IF NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL
		BEGIN
			SET @useExcludeTagTable = 1

			INSERT INTO @cardWithExcludeTags
			SELECT [CardId]
			FROM [fnGetTagsList_0_2](@boardId, @excludedTagsString)

			--PRINT 'Using Exclude Tags'
		END
END /* Region */

	BEGIN /* Region (Card Filtering)  */
		
		DECLARE @filteredCards TABLE (
			Id BIGINT,
			Title NVARCHAR(255),
			Size INT
		)
		
		INSERT INTO @filteredCards
		SELECT DISTINCT
			CC.CardID, 
			CC.Title,
			CC.Size
		FROM [dbo].fact_CardActualStartEndDateContainmentPeriod CP
		JOIN [dbo].[udtf_CurrentCards_0_2] (@boardId) CC ON CC.CardId=CP.CardID
		--LEFT JOIN [dbo].[fnGetStartLanes_0_2] (@boardId,@startLanesString) SL ON SL.LaneId = CP.LaneID
		JOIN [dbo].[udtf_CurrentLanes_0_2](@boardId) L ON CC.LaneId = L.LaneId
		LEFT JOIN @cardWithIncludeTags IT ON IT.CardId = CC.CardId
		LEFT JOIN @cardWithExcludeTags ET ON ET.CardId = CC.CardId
		JOIN [fnGetDefaultCardTypes_0_2](@boardId, @includedCardTypesString) CT ON CT.CardTypeId = CC.TypeID
		WHERE CC.BoardId = @boardId
		AND CC.CardId = (CASE WHEN @useIncludeTagTable = 1 THEN IT.CardId ELSE CC.CardId END)
			AND ((@useExcludeTagTable = 1 AND ET.CardId IS NULL) OR @useExcludeTagTable = 0)
		AND ISNULL(CC.ClassOfServiceId,0) IN (SELECT ISNULL(ClassOfServiceId,0) FROM  [fnGetDefaultClassesOfService_0_2](@boardId, @includedClassesOfServiceString))

	END /* End Region */


	BEGIN /*Region (Card Data) */

		INSERT INTO @CardStatus
		SELECT DISTINCT 
			CC.CardID AS CardID,
			CC.Title AS CardTitle,
			vCC.StartDate AS PlannedStart,
			MAX(CP.ActualStartDate) AS ActualStart,
			vCC.DueDate AS PlannedFinish,
			MAX(CP.ActualFinishDate) AS ActualFinish,
			CASE WHEN MAX(CP.ActualFinishDate) IS NULL THEN 'Not Completed'
			WHEN DATEDIFF(dd, vCC.DueDate, MAX(CP.ActualFinishDate)) > 0 THEN 'Past Due'
			WHEN DATEDIFF(dd, vCC.DueDate, MAX(CP.ActualFinishDate)) < 0 THEN 'Early' 
			WHEN DATEDIFF(dd, vCC.DueDate, MAX(CP.ActualFinishDate)) = 0 THEN 'Completed' END AS CardStatus
		FROM dbo.fact_CardActualStartEndDateContainmentPeriod CP
		JOIN [dbo].[udtf_CurrentCards_0_2] (@boardId) CC ON CC.CardId=CP.CardID
		JOIN [dbo].[vw_dim_Current_Card] vCC
		 ON CC.CardID = vCC.ID
		JOIN @filteredCards C
		 ON C.Id = CP.CardID
	--LEFT JOIN [dbo].[fnGetStartLanes_0_2] (@boardId,@startLanesString) SL ON SL.LaneId = CP.LaneID
		JOIN [dbo].[udtf_CurrentLanes_0_2](@boardId) L ON CC.LaneId = L.LaneId
		LEFT JOIN @dateTable DT 
		 ON DT.[Date]=vCC.DueDate
		WHERE L.BoardId = @boardId
			AND vCC.DueDate IS NOT NULL
		--AND CP.ContainmentStartDate BETWEEN @startDate and dateadd(hh,24,@startDate) 
		--AND C.CardId = (CASE WHEN @useIncludeTagTable = 1 THEN IT.CardId ELSE C.CardId END)
		--AND ((@useExcludeTagTable = 1 AND ET.CardId IS NULL) OR @useExcludeTagTable = 0)
		--AND ISNULL(C.ClassOfServiceId,0) IN (SELECT ISNULL(ClassOfServiceId,0) FROM  [fnGetDefaultClassesOfService_0_2](@boardId, @includedClassesOfServiceString))
		GROUP BY CC.CardID
			,CC.Title
			,vCC.StartDate
			,vCC.DueDate

	END /* End Region */

	BEGIN /* Region (Data Pull) */
		;
		WITH ALLDATES AS (
			SELECT 
			DT.[Date] AS PlannedFinish,
			ST.CardStatus AS CardStatus
			FROM @dateTable DT
			CROSS JOIN @status ST
		)

		SELECT COALESCE(CardID, NULL) AS CardID,
			COALESCE(CardTitle, NULL) AS CardTitle,
			COALESCE(PlannedStart, NULL) AS PlannedStart,
			COALESCE(ActualStart, NULL) AS ActualStart,
			AD.PlannedFinish,
			COALESCE(ActualFinish, NULL) AS ActualFinish,
			AD.CardStatus
		FROM ALLDATES AD
		LEFT JOIN @CardStatus CS ON (AD.PlannedFinish=CS.PlannedFinish AND AD.CardStatus=CS.CardStatus)
		ORDER BY AD.PlannedFinish

	END /* End Region */

END


GO
/****** Object:  StoredProcedure [dbo].[spProcessControl]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[spProcessControl] 
	@boardId BIGINT,
	@userId BIGINT,
	@startDate DATETIME = NULL,
	@endDate DATETIME = NULL,
 	@startLanesString NVARCHAR(MAX) = '',
	@finishLanesString NVARCHAR(MAX) = '',
	@includedTagsString NVARCHAR(MAX) = '',
	@excludedTagsString NVARCHAR(MAX) = '',
	@includedCardTypesString NVARCHAR(MAX) = '',
	@includedClassesOfServiceString NVARCHAR(MAX) = '',
	@offsetHours INT = 0,
	@organizationId BIGINT
AS
BEGIN
	SET NOCOUNT ON;

	INSERT INTO [dbo].[fact_ReportExecution] ([ReportName], [OrgId], [UserId], [BoardId], [ExecutionDate])
	VALUES ('Speed Dashboard', @organizationId, @userId, @boardId, GETUTCDATE())

	DECLARE @returnTable TABLE (
		CardId BIGINT,
		CardTitle NVARCHAR(MAX),
		CardType NVARCHAR(MAX),
		ClassOfService NVARCHAR(MAX),
		Priority NVARCHAR(10),
		CardSize BIGINT,
		StartDate DATETIME,
		FinishDate DATETIME
	)

	--Asserts organization has access to the board, else return empty data
	IF @organizationId <> (SELECT [OrgId] FROM [dbo].[udtf_CurrentBoards](@boardId))
	BEGIN
		SELECT * FROM @returnTable
		RETURN
	END

	--Assert user has access to the board, else return empty data
	IF (SELECT [dbo].[fnGetUserBoardRole](@boardId, @userId)) = 0
	BEGIN
		SELECT * FROM @returnTable
		RETURN
	END
	
BEGIN /* Region (Min and Max Date Calculations) */
		DECLARE @minDate DATETIME
		DECLARE @maxDate DATETIME

		IF (@startDate IS NULL)
		BEGIN
			SELECT @minDate = [dbo].[fnGetMinimumDate](@boardId,@offsetHours)
		END 
		ELSE 
		BEGIN 
			SELECT @minDate = @startDate
		END

		IF (@endDate IS NULL)
		BEGIN
			SELECT @maxDate = DATEADD(HOUR, @offsetHours, dt.[Date])
			FROM [dim_Date] dt
			WHERE dt.[Date] = Convert(DATETIME, DATEDIFF(DAY, 0, GETUTCDATE()))
		END 
		ELSE 
		BEGIN
			SELECT @maxDate = DATEADD(HOUR, @offsetHours, dt.[Date])
			FROM [dim_Date] dt
			WHERE dt.[Date] = @endDate 
		END

END /* Region */

BEGIN /* Region (Include and Exclude Tags)  */
	DECLARE @useIncludeTagTable BIT
	DECLARE @useExcludeTagTable BIT
	SELECT @useIncludeTagTable = 0, @useExcludeTagTable = 0

	DECLARE @cardWithIncludeTags TABLE
	(
		CardId BIGINT
	)

	DECLARE @cardWithExcludeTags TABLE
	(
		CardId BIGINT
	)

	IF (NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL OR NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL)
	BEGIN
		-- Refresh the card tag cache
		EXECUTE [dbo].[usp_RefreshBoardCardCache] @boardId, 1
	END

	IF NULLIF(RTRIM(@includedTagsString),'') IS NOT NULL
	BEGIN
		SET @useIncludeTagTable = 1

		INSERT INTO @cardWithIncludeTags
		SELECT [CardId]
		FROM [fnGetTagsList](@boardId,@includedTagsString)

	END

	IF NULLIF(RTRIM(@excludedTagsString),'') IS NOT NULL
	BEGIN
		SET @useExcludeTagTable = 1

		INSERT INTO @cardWithExcludeTags
		SELECT [CardId]
		FROM [fnGetTagsList](@boardId,@excludedTagsString)

	END
END /* Region */

 
	SELECT DISTINCT CP.CardId
	, C.Title AS CardTitle
	, [CardTypes].Name AS CardType
	, ISNULL([COS].[Title], '* Not Set') AS ClassOfService
	, C.Size AS CardSize, 
	 (CASE C.Priority WHEN 0 THEN 'Low' WHEN 1 THEN 'Normal' WHEN 2 THEN 'High' WHEN 3 THEN 'Critical' END) AS Priority
	, Start.StartDateTime AS StartDate
	, Finish.FinishDateTime AS FinishDate
	FROM [fact_CardLaneContainmentPeriod] CP
		JOIN [dbo].[udtf_CurrentLanes](@boardId) L ON L.LaneId = CP.LaneId
	  JOIN [dbo].[udtf_CurrentCards](@boardId) C ON CP.CardId = C.CardId
	  LEFT JOIN [dbo].[udtf_CurrentClassesOfService](@boardId) [COS] ON [COS].[ClassOfServiceId] = C.ClassOfServiceId
	  JOIN [dbo].[udtf_CurrentCardTypes](@boardId) [CardTypes] ON [CardTypes].CardTypeId = C.TypeId
	  JOIN (SELECT CardId, MIN(DATEADD(HOUR, @offsetHours,dbo.fnGetDateTime ([StartDateKey],[StartTimeKey]))) AS StartDateTime 
			FROM [fact_CardLaneContainmentPeriod] SCP 
			JOIN [fnGetStartLanes](@boardId,@startLanesString) SL ON SL.LaneId = SCP.LaneID
			GROUP BY CardId
			HAVING MIN(DATEADD(HOUR, @offsetHours,dbo.fnGetDateTime ([StartDateKey],[StartTimeKey]))) BETWEEN @minDate AND @maxDate) AS Start ON Start.CardID = CP.CardID
	  JOIN (SELECT CardId, MIN(DATEADD(HOUR, @offsetHours,dbo.fnGetDateTime ([StartDateKey],[StartTimeKey]))) AS FinishDateTime 
			FROM [fact_CardLaneContainmentPeriod] FCP 
			JOIN [fnGetFinishLanes](@boardId,@finishLanesString)  FL ON FL.LaneId = FCP.LaneID
			GROUP BY CardId
			HAVING MIN(DATEADD(HOUR, @offsetHours,dbo.fnGetDateTime ([StartDateKey],[StartTimeKey]))) BETWEEN @minDate AND @maxDate) AS Finish ON Finish.CardID = CP.CardID
	  LEFT JOIN @cardWithIncludeTags IT ON IT.CardId = CP.CardId
	  LEFT JOIN @cardWithExcludeTags ET ON ET.CardId = CP.CardId
	  JOIN [fnGetDefaultCardTypes](@boardId, @includedCardTypesString) CT 
	ON CT.CardTypeId = C.[TypeId] --Filter on Card Type
	  WHERE CP.CardID = (CASE WHEN @useIncludeTagTable = 1 THEN IT.CardId ELSE CP.CardID END)
			AND ((@useExcludeTagTable = 1 AND ET.CardId IS NULL) OR @useExcludeTagTable = 0)
		AND ISNULL(C.[ClassOfServiceId], 0) IN (SELECT ISNULL(ClassOfServiceId, 0) FROM  [fnGetDefaultClassesOfService](@boardId, @includedClassesOfServiceString)) --Filter on Class of Service
		AND CP.ContainmentEndDate IS NULL
END






GO
/****** Object:  StoredProcedure [dbo].[usp_RefreshBoardCardCache]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[usp_RefreshBoardCardCache] 
	@boardId BIGINT
	, @refreshTags BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	
	-- If the board in question has been deleted (or archived, whatever)
	-- then blow away this board's cache since it shouldn't be needed anymore
	IF NOT EXISTS (SELECT [BoardId] FROM [dbo].[udtf_CurrentBoards](@boardId))
	BEGIN
		--PRINT 'Board ' + CAST(@boardId AS VARCHAR) + ' not found, deleting'
		DELETE FROM [dbo].[_BoardCardCache] WHERE [BoardId] = @boardId
		RETURN
	END

	-- Well, it's not deleted so let's do some work
	ELSE
	BEGIN

		--PRINT 'Updating cache for board ' + CAST(@boardId AS VARCHAR)
		-- We're going to merge in the current DimRowId values for all the current card
		-- records into our cache table. The intent is to maintain one single list of
		-- the DimRowId values that represent the current cards for this board.

		MERGE [dbo].[_BoardCardCache] AS target
		USING (
			SELECT 
				@boardId AS [BoardId]
				, [Card].[CardId]
				, [Card].[DimRowId]
			FROM [dbo].[udtf_CurrentCards_0_3](@boardId) [Card]
							--this join eliminates dup open containments
				join	
               (select max(ContainmentStartDate) as maxdim, [CardId] from 
                [dbo].[udtf_CurrentCards_0_3](@boardId)
                group by [CardId]) dup on [Card].ContainmentStartDate = dup.maxdim
				and 
				[Card].CardId = dup.CardId

		) AS source ([BoardId], [CardId], [DimRowId])
		ON (target.[BoardId] = source.[BoardId] AND target.[CardId] = source.[CardId])
		-- This means that we found the board and card ID in the cache but that the current
		-- DimRowId value is now different, meaning that the card has changed for some reason.
		WHEN MATCHED AND target.[DimRowId] <> source.[DimRowId]
			-- Update our cache to reflect the new correct record from dim_Card
			THEN UPDATE SET target.[DimRowId] = source.[DimRowId]
		-- This means that there is a board and card ID in the cache that isn't currently listed
		-- in the set of current cards, likely meaning that it has been deleted
		WHEN NOT MATCHED BY SOURCE
			-- So, delete this value from the cache
			THEN DELETE
		-- This means that we found a card in the current cards list that does not have a cache
		-- entry, so add it.
		WHEN NOT MATCHED BY TARGET
			-- Adding the entry to the cache
			THEN INSERT ([BoardId], [CardId], [DimRowId]) VALUES (@boardId, [CardId], [DimRowId]);

		-- Check if the caller asked us to refresh the tags - hopefully they only do so when
		-- someone has requested to filter by tags.
		IF (@refreshTags = 1)
		BEGIN

			--PRINT 'Refreshing tags for board ' + CAST(@boardId AS VARCHAR)
			-- This table will store the list of cards whose DimRowId has changed
			-- since the last time the board card cache was updated.
			DECLARE @cardsToProcess TABLE (
				[DimRowId] BIGINT
				, [CardId] BIGINT
				, [TagChecksum] INT
			)

			--PRINT 'Finding cards to process'
			-- Add cards...
			INSERT INTO @cardsToProcess ([CardId], [DimRowId], [TagChecksum])
			SELECT bcc.[CardId], bcc.[DimRowId], dc.[cs_Tags]
			FROM [dbo].[_BoardCardCache] bcc
			INNER JOIN [dbo].[dim_Card] dc
				ON bcc.[DimRowId] = dc.[DimRowId]
			-- ...that have no associated card tag cache row (haven't been processed yet)...
			LEFT JOIN [dbo].[_CardTagCache] ctc
				ON bcc.[BoardId] = @boardId
				AND bcc.[CardId] = ctc.[CardId]
			WHERE ctc.[CardTagCacheId] IS NULL
			-- ...or have been processed but the tag checksum has changed
			OR (ctc.[TagChecksum] IS NULL OR dc.[cs_Tags] <> ctc.[TagChecksum])

			-- If there are no "new" cards to process, then return
			IF (SELECT COUNT(0) FROM @cardsToProcess) = 0
			BEGIN
				--PRINT 'No cards to process for board ' + CAST(@boardId AS VARCHAR) + ', quitting'
				RETURN
			END

			--PRINT 'Merging into card tag cache for board ' + CAST(@boardId AS VARCHAR)
			-- Upsert the card tag cache table to update the checksums for the cards we're processing
			MERGE [dbo].[_CardTagCache] AS target
			USING (
				SELECT DISTINCT
					@boardId AS [BoardId]
					, [CardId]
					, [TagChecksum]
				FROM @cardsToProcess
			) AS source ([BoardId], [CardId], [TagChecksum])
			ON (target.[BoardId] = source.[BoardId] AND target.[CardId] = source.[CardId])
			-- Card Tags have changed, update the checksum
			WHEN MATCHED AND target.[TagChecksum] <> source.[TagChecksum]
				THEN UPDATE SET target.[TagChecksum] = source.[TagChecksum]
			-- No cache entry for this card, add it
			WHEN NOT MATCHED BY TARGET
				THEN INSERT ([BoardId], [CardId], [TagChecksum]) VALUES (@boardId, source.[CardId], source.[TagChecksum]);

			-- This is where we're going to store the list of individual parsed tag values
			-- we've grabbed from the cards. There will be multiple records in this table
			-- for cards with multiple tags
			DECLARE @tags TABLE (
				[CardId] BIGINT
				, [TagChecksum] INT
				, [TagValue] NVARCHAR(2000)
				, [TagId] BIGINT
			)

			-- Vars while we're iterating
			DECLARE @currentCardId BIGINT
			DECLARE @currentDimRowId BIGINT
			DECLARE @currentTags NVARCHAR(2000)
			DECLARE @currentTagsChecksum INT

			-- Probably should be passed in as an argument, but shut up.
			DECLARE @delimiter NVARCHAR(10) = ','

			--PRINT 'Beginning work loop for board ' + CAST(@boardId AS VARCHAR)
			-- Loop through the cards we need to process and grab their lists of
			-- card tag values and store them in @tags
			WHILE (SELECT COUNT(0) FROM @cardsToProcess) > 0
			BEGIN

				SELECT TOP 1 
					@currentCardId = [CardId]
					, @currentDimRowId = [DimRowId]
				FROM @cardsToProcess
				ORDER BY [CardId]

				--PRINT 'Current card ID is ' + CAST(@currentCardId AS VARCHAR) + ', DimRowId is ' + CAST(@currentDimRowId AS VARCHAR)

				SELECT 
					@currentTags = [Tags]
				FROM [dbo].[dim_Card] dc
				WHERE dc.[DimRowId] = @currentDimRowId

				--PRINT 'Current tags are ' + ISNULL(@CAST(@currentTags AS NVARCHAR), 'null')

				INSERT INTO @tags ([CardId], [TagChecksum], [TagValue])
				SELECT @currentCardId, CHECKSUM([Value]), [Value]
				FROM [dbo].[udtf_SplitString](@currentTags, @delimiter)

				--PRINT 'Deleting from cards to process'
				DELETE FROM @cardsToProcess WHERE [DimRowId] = @currentDimRowId

			END

			--PRINT 'Merging board tags for board ID ' + CAST(@boardId AS VARCHAR)
			-- Upsert into the board tag table any new card tags
			MERGE [dbo].[_BoardTag] AS target
			USING (
				SELECT DISTINCT
					@boardId AS [BoardId]
					, [TagChecksum]
					, [TagValue]
					, [TagId]
				FROM @tags
			) AS source ([BoardId], [TagChecksum], [TagValue], [TagId])
			ON (target.[BoardId] = source.[BoardId] AND target.[cs_Tag] = source.[TagChecksum])
			WHEN NOT MATCHED BY TARGET
				-- Adding the entry to the cache
				THEN INSERT ([BoardId], [Tag]) VALUES (@boardId, [TagValue]);

			--PRINT 'Updating temp tag table'
			-- Update the temporary tags table with the tag ID values for new tags
			UPDATE t
			SET t.[TagId] = bt.[BoardTagId]
			FROM @tags t
			INNER JOIN [dbo].[_BoardTag] bt
				ON t.[TagChecksum] = bt.[cs_Tag]
			WHERE bt.[BoardId] = @boardId

			DELETE [dbo].[_BoardCardTag]
			FROM [dbo].[_BoardCardTag] bcc
			INNER JOIN @tags t
				ON t.[CardId] = bcc.[CardId]

			--PRINT 'Merging board card tags'
			-- Now, make the BoardCardTag table match the current list of card tag values for cards that have been updated
			MERGE [dbo].[_BoardCardTag] AS target
			USING (
				SELECT
					[CardId]
					, [TagId]
				FROM @tags
			) AS source ([CardId], [TagId])
			ON (target.[CardId] = source.[CardId] AND target.[BoardTagId] = source.[TagId])
			--WHEN NOT MATCHED BY SOURCE
			--	THEN DELETE
			WHEN NOT MATCHED BY TARGET
				THEN INSERT ([BoardTagId], [CardId]) VALUES (source.[TagId], source.[CardId]);
			
		END

	END

END




GO
/****** Object:  StoredProcedure [dbo].[usp_RefreshBoardCardCache_new]    Script Date: 11/7/2016 8:56:50 PM ******/
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE PROCEDURE [dbo].[usp_RefreshBoardCardCache_new] 
	@boardId BIGINT
	, @refreshTags BIT = 0
AS
BEGIN
	SET NOCOUNT ON;
	
	-- If the board in question has been deleted (or archived, whatever)
	-- then blow away this board's cache since it shouldn't be needed anymore
	IF NOT EXISTS (SELECT [BoardId] FROM [dbo].[udtf_CurrentBoards](@boardId))
	BEGIN
		--PRINT 'Board ' + CAST(@boardId AS VARCHAR) + ' not found, deleting'
		DELETE FROM [dbo].[_BoardCardCache] WHERE [BoardId] = @boardId
		RETURN
	END

	-- Well, it's not deleted so let's do some work
	ELSE
	BEGIN

		--PRINT 'Updating cache for board ' + CAST(@boardId AS VARCHAR)
		-- We're going to merge in the current DimRowId values for all the current card
		-- records into our cache table. The intent is to maintain one single list of
		-- the DimRowId values that represent the current cards for this board.

		MERGE [dbo].[_BoardCardCache] AS target
		USING (
			SELECT 
				@boardId AS [BoardId]
				, [Card].[CardId]
				, [Card].[DimRowId]
			FROM [dbo].[udtf_CurrentCards_0_3](@boardId) [Card]
							--this join eliminates dup open containments
				join	
               (select max(ContainmentStartDate) as maxdim, [CardId] from 
                [dbo].[udtf_CurrentCards_0_3](@boardId)
                group by [CardId]) dup on [Card].ContainmentStartDate = dup.maxdim
				and 
				[Card].CardId = dup.CardId

		) AS source ([BoardId], [CardId], [DimRowId])
		ON (target.[BoardId] = source.[BoardId] AND target.[CardId] = source.[CardId])
		-- This means that we found the board and card ID in the cache but that the current
		-- DimRowId value is now different, meaning that the card has changed for some reason.
		WHEN MATCHED AND target.[DimRowId] <> source.[DimRowId]
			-- Update our cache to reflect the new correct record from dim_Card
			THEN UPDATE SET target.[DimRowId] = source.[DimRowId]
		-- This means that there is a board and card ID in the cache that isn't currently listed
		-- in the set of current cards, likely meaning that it has been deleted
		WHEN NOT MATCHED BY SOURCE
			-- So, delete this value from the cache
			THEN DELETE
		-- This means that we found a card in the current cards list that does not have a cache
		-- entry, so add it.
		WHEN NOT MATCHED BY TARGET
			-- Adding the entry to the cache
			THEN INSERT ([BoardId], [CardId], [DimRowId]) VALUES (@boardId, [CardId], [DimRowId]);

		-- Check if the caller asked us to refresh the tags - hopefully they only do so when
		-- someone has requested to filter by tags.
		IF (@refreshTags = 1)
		BEGIN

			--PRINT 'Refreshing tags for board ' + CAST(@boardId AS VARCHAR)
			-- This table will store the list of cards whose DimRowId has changed
			-- since the last time the board card cache was updated.
			DECLARE @cardsToProcess TABLE (
				[DimRowId] BIGINT
				, [CardId] BIGINT
				, [TagChecksum] INT
			)

			--PRINT 'Finding cards to process'
			-- Add cards...
			INSERT INTO @cardsToProcess ([CardId], [DimRowId], [TagChecksum])
			SELECT bcc.[CardId], bcc.[DimRowId], dc.[cs_Tags]
			FROM [dbo].[_BoardCardCache] bcc
			INNER JOIN [dbo].[dim_Card] dc
				ON bcc.[DimRowId] = dc.[DimRowId]
			-- ...that have no associated card tag cache row (haven't been processed yet)...
			LEFT JOIN [dbo].[_CardTagCache] ctc
				ON bcc.[BoardId] = @boardId
				AND bcc.[CardId] = ctc.[CardId]
			WHERE ctc.[CardTagCacheId] IS NULL
			-- ...or have been processed but the tag checksum has changed
			OR (ctc.[TagChecksum] IS NULL OR dc.[cs_Tags] <> ctc.[TagChecksum])

			-- If there are no "new" cards to process, then return
			IF (SELECT COUNT(0) FROM @cardsToProcess) = 0
			BEGIN
				--PRINT 'No cards to process for board ' + CAST(@boardId AS VARCHAR) + ', quitting'
				RETURN
			END

			--PRINT 'Merging into card tag cache for board ' + CAST(@boardId AS VARCHAR)
			-- Upsert the card tag cache table to update the checksums for the cards we're processing
			MERGE [dbo].[_CardTagCache] AS target
			USING (
				SELECT DISTINCT
					@boardId AS [BoardId]
					, [CardId]
					, [TagChecksum]
				FROM @cardsToProcess
			) AS source ([BoardId], [CardId], [TagChecksum])
			ON (target.[BoardId] = source.[BoardId] AND target.[CardId] = source.[CardId])
			-- Card Tags have changed, update the checksum
			WHEN MATCHED AND target.[TagChecksum] <> source.[TagChecksum]
				THEN UPDATE SET target.[TagChecksum] = source.[TagChecksum]
			-- No cache entry for this card, add it
			WHEN NOT MATCHED BY TARGET
				THEN INSERT ([BoardId], [CardId], [TagChecksum]) VALUES (@boardId, source.[CardId], source.[TagChecksum]);

			-- This is where we're going to store the list of individual parsed tag values
			-- we've grabbed from the cards. There will be multiple records in this table
			-- for cards with multiple tags
			DECLARE @tags TABLE (
				[CardId] BIGINT
				, [TagChecksum] INT
				, [TagValue] NVARCHAR(2000)
				, [TagId] BIGINT
			)

			-- Vars while we're iterating
			DECLARE @currentCardId BIGINT
			DECLARE @currentDimRowId BIGINT
			DECLARE @currentTags NVARCHAR(2000)
			DECLARE @currentTagsChecksum INT

			-- Probably should be passed in as an argument, but shut up.
			DECLARE @delimiter NVARCHAR(10) = ','

			--PRINT 'Beginning work loop for board ' + CAST(@boardId AS VARCHAR)
			-- Loop through the cards we need to process and grab their lists of
			-- card tag values and store them in @tags
			WHILE (SELECT COUNT(0) FROM @cardsToProcess) > 0
			BEGIN

				SELECT TOP 1 
					@currentCardId = [CardId]
					, @currentDimRowId = [DimRowId]
				FROM @cardsToProcess
				ORDER BY [CardId]

				--PRINT 'Current card ID is ' + CAST(@currentCardId AS VARCHAR) + ', DimRowId is ' + CAST(@currentDimRowId AS VARCHAR)

				SELECT 
					@currentTags = [Tags]
				FROM [dbo].[dim_Card] dc
				WHERE dc.[DimRowId] = @currentDimRowId

				--PRINT 'Current tags are ' + ISNULL(@CAST(@currentTags AS NVARCHAR), 'null')

				INSERT INTO @tags ([CardId], [TagChecksum], [TagValue])
				SELECT @currentCardId, CHECKSUM([Value]), [Value]
				FROM [dbo].[udtf_SplitString](@currentTags, @delimiter)

				--PRINT 'Deleting from cards to process'
				DELETE FROM @cardsToProcess WHERE [DimRowId] = @currentDimRowId

			END

			--PRINT 'Merging board tags for board ID ' + CAST(@boardId AS VARCHAR)
			-- Upsert into the board tag table any new card tags
			MERGE [dbo].[_BoardTag] AS target
			USING (
				SELECT DISTINCT
					@boardId AS [BoardId]
					, [TagChecksum]
					, [TagValue]
					, [TagId]
				FROM @tags
			) AS source ([BoardId], [TagChecksum], [TagValue], [TagId])
			ON (target.[BoardId] = source.[BoardId] AND target.[cs_Tag] = source.[TagChecksum])
			WHEN NOT MATCHED BY TARGET
				-- Adding the entry to the cache
				THEN INSERT ([BoardId], [Tag]) VALUES (@boardId, [TagValue]);

			--PRINT 'Updating temp tag table'
			-- Update the temporary tags table with the tag ID values for new tags
			UPDATE t
			SET t.[TagId] = bt.[BoardTagId]
			FROM @tags t
			INNER JOIN [dbo].[_BoardTag] bt
				ON t.[TagChecksum] = bt.[cs_Tag]
			WHERE bt.[BoardId] = @boardId

			DELETE [dbo].[_BoardCardTag]
			FROM [dbo].[_BoardCardTag] bcc
			INNER JOIN @tags t
				ON t.[CardId] = bcc.[CardId]

			--PRINT 'Merging board card tags'
			-- Now, make the BoardCardTag table match the current list of card tag values for cards that have been updated
			MERGE [dbo].[_BoardCardTag] AS target
			USING (
				SELECT
					[CardId]
					, [TagId]
				FROM @tags
			) AS source ([CardId], [TagId])
			ON (target.[CardId] = source.[CardId] AND target.[BoardTagId] = source.[TagId])
			--WHEN NOT MATCHED BY SOURCE
			--	THEN DELETE
			WHEN NOT MATCHED BY TARGET
				THEN INSERT ([BoardTagId], [CardId]) VALUES (source.[TagId], source.[CardId]);
			
		END

	END

END




GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The unique identifier of a migration script file. This value is stored within the <Migration /> Xml fragment within the header of the file itself.

Note that it is possible for this value to repeat in the [__MigrationLog] table. In the case of programmable object scripts, a record will be inserted with a particular ID each time a change is made to the source file and subsequently deployed.

In the case of a migration, you may see the same [migration_id] repeated, but only in the scenario where the "Mark As Deployed" button/command has been run.' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'__MigrationLog', @level2type=N'COLUMN',@level2name=N'migration_id'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'A SHA256 representation of the migration script file at the time of build.  This value is used to determine whether a migration has been changed since it was deployed. In the case of a programmable object script, a different checksum will cause the migration to be redeployed.
Note: if any variables have been specified as part of a deployment, this will not affect the checksum value.' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'__MigrationLog', @level2type=N'COLUMN',@level2name=N'script_checksum'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The name of the migration script file on disk, at the time of build.
If Semantic Versioning has been enabled, then this value will contain the full relative path from the root of the project folder. If it is not enabled, then it will simply contain the filename itself.' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'__MigrationLog', @level2type=N'COLUMN',@level2name=N'script_filename'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The date/time that the migration finished executing. This value is populated using the SYSDATETIME function in SQL Server 2008+ or by using GETDATE in SQL Server 2005.' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'__MigrationLog', @level2type=N'COLUMN',@level2name=N'complete_dt'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The executing user at the time of deployment (populated using the SYSTEM_USER function).' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'__MigrationLog', @level2type=N'COLUMN',@level2name=N'applied_by'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'This column contains a number of potential states:

0 - Marked As Deployed: The migration was not executed.
1- Deployed: The migration was executed successfully.
2- Imported: The migration was generated by importing from this DB.

"Marked As Deployed" and "Imported" are similar in that the migration was not executed on this database; it was was only marked as such to prevent it from executing during subsequent deployments.' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'__MigrationLog', @level2type=N'COLUMN',@level2name=N'deployed'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'The semantic version that this migration was created under. In ReadyRoll projects, a folder can be given a version number, e.g. 1.0.0, and one or more migration scripts can be stored within that folder to provide logical grouping of related database changes.' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'__MigrationLog', @level2type=N'COLUMN',@level2name=N'version'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'If you have enabled SQLCMD Packaging in your ReadyRoll project, or if you are using Octopus Deploy, this will be the version number that your database package was stamped with at build-time.' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'__MigrationLog', @level2type=N'COLUMN',@level2name=N'package_version'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'If you are using Octopus Deploy, you can use the value in this column to look-up which release was responsible for deploying this migration.
If deploying via PowerShell, set the $ReleaseVersion variable to populate this column.
If deploying via Visual Studio, this column will always be NULL.' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'__MigrationLog', @level2type=N'COLUMN',@level2name=N'release_version'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'An auto-seeded numeric identifier that can be used to determine the order in which migrations were deployed.' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'__MigrationLog', @level2type=N'COLUMN',@level2name=N'sequence_no'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'This table is required by ReadyRoll SQL Projects to keep track of which migrations have been executed during deployment. Please do not alter or remove this table from the database.' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'TABLE',@level1name=N'__MigrationLog'
GO
EXEC sys.sp_addextendedproperty @name=N'MS_Description', @value=N'This view is required by ReadyRoll SQL Projects to determine whether a migration should be executed during a deployment. The view lists the most recent [__MigrationLog] entry for a given [migration_id], which is needed to determine whether a particular programmable object script needs to be (re)executed: a non-matching checksum on the current [__MigrationLog] entry will trigger the execution of a programmable object script. Please do not alter or remove this table from the database.' , @level0type=N'SCHEMA',@level0name=N'dbo', @level1type=N'VIEW',@level1name=N'__MigrationLogCurrent'
GO
