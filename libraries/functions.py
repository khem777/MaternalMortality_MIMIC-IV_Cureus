def get_statistics_columns(p_df, p_columns):

    resume_statistic = p_df[p_columns].agg(["count", "mean", "median", "min", "max"]).transpose()

    mode_val = p_df[p_columns].mode().iloc[0]  # Takes only the first mode in case of a tie
    mode_val.name = 'mode'
    resume_statistic['mode'] = mode_val
    return resume_statistic


