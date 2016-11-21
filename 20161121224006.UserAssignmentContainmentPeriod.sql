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
