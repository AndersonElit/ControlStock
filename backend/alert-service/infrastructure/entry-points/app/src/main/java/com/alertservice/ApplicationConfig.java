package com.alertservice;

import org.springframework.context.annotation.ComponentScan;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.FilterType;

@Configuration
@ComponentScan(
        basePackages = {
                "com.alertservice.usecases",
                "com.alertservice.restapi",
                "com.alertservice.app"
        },
        includeFilters = {
                @ComponentScan.Filter(
                        type = FilterType.REGEX,
                        pattern = ".*UseCase?$"
                )
        },
        useDefaultFilters = false
)
public class ApplicationConfig {
}
